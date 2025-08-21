// smart_datetime_detector.cpp
// C++17+ (works even better with C++20). Single-file utility for inferring CSV date/time columns & formats.

#include <algorithm>
#include <array>
#include <cctype>
#include <chrono>
#include <ctime>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <locale>
#include <optional>
#include <regex>
#include <sstream>
#include <string>
#include <tuple>
#include <unordered_map>
#include <vector>

namespace csvdt {

enum class Role { Unknown, Date, Time, DateTime, EpochSeconds, EpochMillis };

struct DetectedColumn {
    size_t index{};
    Role role{Role::Unknown};
    std::string format;     // strptime/get_time-compatible format (empty for epoch)
    double confidence{0.0}; // 0..1 based on sample parse rate (+header boost)
    std::string header;
};

struct DetectionResult {
    // Either: datetime_col has value; or: date_col and time_col have values
    std::optional<DetectedColumn> datetime_col;
    std::optional<DetectedColumn> date_col;
    std::optional<DetectedColumn> time_col;
    char delimiter{','};
    std::vector<DetectedColumn> all_columns; // for inspection/debug
};

// --- small helpers ----------------------------------------------------------

static inline std::string trim(const std::string &s) {
    size_t a = 0, b = s.size();
    while (a < b && std::isspace(static_cast<unsigned char>(s[a]))) ++a;
    while (b > a && std::isspace(static_cast<unsigned char>(s[b-1]))) --b;
    return s.substr(a, b - a);
}

static inline std::string tolower_copy(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c){ return std::tolower(c); });
    return s;
}

static char sniff_delimiter(const std::string &headerLine) {
    // Look for common delimiters; choose the one with the most occurrences
    const std::array<char,4> cands{',',';','\t','|'};
    size_t bestCount = 0;
    char best = ',';
    for (char d : cands) {
        size_t cnt = std::count(headerLine.begin(), headerLine.end(), d);
        if (cnt > bestCount) { bestCount = cnt; best = d; }
    }
    return best;
}

// Basic CSV splitter (handles quoted fields with the chosen delimiter)
static std::vector<std::string> split_csv_line(const std::string &line, char delim) {
    std::vector<std::string> out;
    std::string cur;
    bool inQuotes = false;
    for (size_t i=0;i<line.size();++i) {
        char c = line[i];
        if (c == '"') {
            if (inQuotes && i+1<line.size() && line[i+1]=='"') {
                cur.push_back('"'); // escaped quote
                ++i;
            } else {
                inQuotes = !inQuotes;
            }
        } else if (c == delim && !inQuotes) {
            out.push_back(cur);
            cur.clear();
        } else {
            cur.push_back(c);
        }
    }
    out.push_back(cur);
    return out;
}

// Try parsing with std::get_time for a given format (after normalizing string).
static bool try_get_time(const std::string &value, const std::string &fmt) {
    std::tm tm{}; tm.tm_isdst = -1;
    std::istringstream iss(value);
    iss.imbue(std::locale::classic());
    iss >> std::get_time(&tm, fmt.c_str());
    return !iss.fail();
}

// Normalize ISO-8601-ish strings so get_time can cope better:
// - Strip trailing 'Z'
// - Strip timezone offsets like +hh:mm or -hhmm (we ignore the offset for format detection)
// - Remove fractional seconds ".sss..." but remember we did it
static std::string normalize_iso_like(std::string s) {
    s = trim(s);
    // Remove trailing Z
    if (!s.empty() && (s.back()=='Z' || s.back()=='z')) {
        s.pop_back();
        s = trim(s);
    }
    // Remove timezone offset (common forms: +hh:mm, -hh:mm, +hhmm, -hhmm)
    static const std::regex tz1(R"(([+-]\d{2}:\d{2})$)");
    static const std::regex tz2(R"(([+-]\d{4})$)");
    s = std::regex_replace(s, tz1, "");
    s = std::regex_replace(s, tz2, "");
    s = trim(s);
    // Remove fractional .sss...
    static const std::regex frac(R"((\.\d{1,9}))");
    s = std::regex_replace(s, frac, "");
    return s;
}

struct FormatHit {
    std::string fmt;
    size_t hits{};
};

static bool is_epoch_seconds(const std::string &s) {
    static const std::regex re(R"(^\d{10}$)");
    return std::regex_match(trim(s), re);
}

static bool is_epoch_millis(const std::string &s) {
    static const std::regex re(R"(^\d{13}$)");
    return std::regex_match(trim(s), re);
}

// Score a column against candidate formats; return best format and score
static std::pair<std::string,double> best_format_for(
    const std::vector<std::string> &samples,
    const std::vector<std::string> &formats,
    bool normalize_iso=false)
{
    std::vector<FormatHit> tally;
    tally.reserve(formats.size());
    for (auto &f: formats) tally.push_back({f,0});

    size_t nonEmpty = 0;
    for (auto s : samples) {
        s = trim(s);
        if (s.empty()) continue;
        ++nonEmpty;
        std::string test = normalize_iso ? normalize_iso_like(s) : s;
        for (auto &fh : tally) {
            if (try_get_time(test, fh.fmt)) {
                fh.hits++;
            }
        }
    }
    // If column is empty in all sample rows, avoid division by zero
    if (nonEmpty == 0) return {"", 0.0};

    // Pick best
    auto it = std::max_element(tally.begin(), tally.end(),
        [](const FormatHit&a, const FormatHit&b){ return a.hits < b.hits; });

    double score = static_cast<double>(it->hits) / static_cast<double>(nonEmpty);
    return {it->fmt, score};
}

// Header “prior” boost
static double header_prior(const std::string &hdr, Role role) {
    std::string h = tolower_copy(hdr);
    auto has = [&](std::initializer_list<const char*> kws){
        for (auto k: kws) if (h.find(k) != std::string::npos) return true;
        return false;
    };
    double bonus = 0.0;
    if (role == Role::DateTime) {
        if (has({"datetime","timestamp","ts","date_time","date-time"})) bonus += 0.15;
    }
    if (role == Role::Date) {
        if (has({"date","day","ymd","mdy","dmy"})) bonus += 0.10;
    }
    if (role == Role::Time) {
        if (has({"time","hour","minute","second"})) bonus += 0.10;
    }
    // UTC hints
    if (has({"utc","zulu","tz"})) bonus += 0.05;
    return bonus;
}

// --- main detection ---------------------------------------------------------

class Detector {
public:
    struct Table {
        char delim{','};
        std::vector<std::string> headers;
        std::vector<std::vector<std::string>> rows; // sampled rows
    };

    static Table read_csv_sample(const std::string &path, size_t max_rows=1000) {
        std::ifstream in(path);
        if (!in) throw std::runtime_error("Cannot open file: " + path);
        std::string headerLine;
        if (!std::getline(in, headerLine)) throw std::runtime_error("Empty file: " + path);
        char delim = sniff_delimiter(headerLine);
        auto headers = split_csv_line(headerLine, delim);

        std::vector<std::vector<std::string>> rows;
        rows.reserve(max_rows);
        std::string line;
        while (rows.size() < max_rows && std::getline(in, line)) {
            if (line.empty()) continue;
            rows.push_back(split_csv_line(line, delim));
            // Normalize row length by padding or trimming
            if (rows.back().size() < headers.size()) rows.back().resize(headers.size());
            if (rows.back().size() > headers.size()) rows.back().resize(headers.size());
        }
        return Table{delim, headers, rows};
    }

    static DetectionResult detect(const Table &t) {
        const std::vector<std::string> &hdrs = t.headers;
        const auto &rows = t.rows;
        const size_t cols = hdrs.size();

        auto column_samples = [&](size_t c)->std::vector<std::string>{
            std::vector<std::string> v; v.reserve(rows.size());
            for (auto &r: rows) if (c < r.size()) v.push_back(r[c]);
            return v;
        };

        // Candidate format banks
        const std::vector<std::string> date_formats = {
            "%Y-%m-%d", "%Y/%m/%d", "%m/%d/%Y", "%d/%m/%Y", "%d.%m.%Y",
            "%d-%b-%Y", "%b %d, %Y", "%Y%m%d"
        };
        const std::vector<std::string> time_formats = {
            "%H:%M:%S", "%H:%M", "%I:%M:%S %p", "%I:%M %p", "%H%M%S", "%H%M"
        };
        // Some common datetime mixes (we also try ISO-ish via normalization)
        const std::vector<std::string> datetime_formats = {
            "%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M",
            "%m/%d/%Y %H:%M:%S", "%m/%d/%Y %H:%M",
            "%d/%m/%Y %H:%M:%S", "%d/%m/%Y %H:%M",
            "%Y/%m/%d %H:%M:%S", "%Y/%m/%d %H:%M",
            "%d-%b-%Y %H:%M:%S", "%d-%b-%Y %H:%M",
            "%Y%m%d %H%M%S", "%Y-%m-%d_%H-%M-%S"
        };
        // ISO-like (we normalize then try)
        const std::vector<std::string> iso_like = {
            "%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M"
        };

        std::vector<DetectedColumn> detected;
        detected.reserve(cols);

        for (size_t c=0;c<cols;++c) {
            auto samples = column_samples(c);
            // Pre-trim samples for epoch detection
            size_t nonEmpty=0, secHits=0, msHits=0;
            for (auto &s : samples) {
                std::string x = trim(s);
                if (x.empty()) continue;
                ++nonEmpty;
                if (is_epoch_seconds(x)) ++secHits;
                else if (is_epoch_millis(x)) ++msHits;
            }

            double epochScoreSec = nonEmpty? double(secHits)/nonEmpty : 0.0;
            double epochScoreMs  = nonEmpty? double(msHits)/nonEmpty : 0.0;

            // Try date/time/datetime banks
            auto [bestDateFmt, dateScore] = best_format_for(samples, date_formats, false);
            auto [bestTimeFmt, timeScore] = best_format_for(samples, time_formats, false);
            auto [bestDTFmt,  dtScore1]  = best_format_for(samples, datetime_formats, false);
            auto [bestIsoFmt, dtScore2]  = best_format_for(samples, iso_like, true);

            double dtScore = std::max(dtScore1, dtScore2);
            std::string dtFmt = (dtScore1 >= dtScore2) ? bestDTFmt : bestIsoFmt;

            // Decide role
            Role role = Role::Unknown;
            std::string fmt;
            double score = 0.0;

            // Start with the best-scoring of the four “modes”
            struct Cand { Role role; std::string fmt; double score; };
            std::vector<Cand> cands;
            cands.push_back({Role::DateTime, dtFmt, dtScore});
            cands.push_back({Role::Date,     bestDateFmt, dateScore});
            cands.push_back({Role::Time,     bestTimeFmt, timeScore});
            cands.push_back({Role::EpochSeconds, "", epochScoreSec});
            cands.push_back({Role::EpochMillis,  "", epochScoreMs});

            // Add header prior bonus
            for (auto &cd : cands) {
                cd.score += header_prior(hdrs[c], cd.role);
            }
            auto best = std::max_element(cands.begin(), cands.end(),
                [](const Cand&a, const Cand&b){ return a.score < b.score; });

            role  = best->role;
            fmt   = best->fmt;
            score = std::min(best->score, 1.0); // cap

            detected.push_back(DetectedColumn{c, role, fmt, score, hdrs[c]});
        }

        // Decide final mapping:
        DetectionResult res;
        res.delimiter = t.delim;
        res.all_columns = detected;

        // Prefer a single strong DateTime / Epoch column
        auto pick_dt = [&](Role r)->std::optional<DetectedColumn>{
            const double THRESH = 0.70;
            DetectedColumn best{};
            bool found=false;
            for (auto &d: detected) {
                if (d.role == r && d.confidence >= THRESH) {
                    if (!found || d.confidence > best.confidence) { best = d; found = true; }
                }
            }
            if (found) return best;
            return std::nullopt;
        };

        if (auto msec = pick_dt(Role::EpochMillis)) { res.datetime_col = msec; return res; }
        if (auto sec  = pick_dt(Role::EpochSeconds)) { res.datetime_col = sec; return res; }
        if (auto dt   = pick_dt(Role::DateTime)) { res.datetime_col = dt; return res; }

        // Otherwise, try separate Date + Time with decent scores
        DetectedColumn bestDate{}, bestTime{};
        bool haveDate=false, haveTime=false;
        for (auto &d: detected) {
            if (d.role==Role::Date && d.confidence>=0.60) {
                if (!haveDate || d.confidence > bestDate.confidence) { bestDate = d; haveDate = true; }
            }
            if (d.role==Role::Time && d.confidence>=0.60) {
                if (!haveTime || d.confidence > bestTime.confidence) { bestTime = d; haveTime = true; }
            }
        }
        if (haveDate && haveTime) {
            res.date_col = bestDate;
            res.time_col = bestTime;
            return res;
        }

        // As a fallback, expose whatever had the highest score among all roles.
        auto overall = std::max_element(detected.begin(), detected.end(),
            [](const DetectedColumn&a, const DetectedColumn&b){ return a.confidence < b.confidence; });

        if (overall != detected.end()) {
            if (overall->role == Role::Date) res.date_col = *overall;
            else if (overall->role == Role::Time) res.time_col = *overall;
            else res.datetime_col = *overall;
        }
        return res;
    }
};

} // namespace csvdt

// -------------------- demo usage --------------------
#ifdef CSV_DT_DEMO_MAIN
int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: smart_datetime_detector <csv-file> [max_rows]\n";
        return 1;
    }
    std::string path = argv[1];
    size_t max_rows = (argc >= 3) ? static_cast<size_t>(std::stoul(argv[2])) : 1000;

    try {
        auto table = csvdt::Detector::read_csv_sample(path, max_rows);
        auto res   = csvdt::Detector::detect(table);

        std::cout << "Delimiter: '" << (res.delimiter=='\t' ? ' ' : res.delimiter) << "' (\\t shown as space)\n";
        std::cout << "Headers:\n";
        for (size_t i=0;i<table.headers.size();++i) {
            std::cout << "  ["<<i<<"] " << table.headers[i] << "\n";
        }
        std::cout << "\nColumn roles (all):\n";
        auto role_to_str = [](csvdt::Role r){
            switch (r) {
                case csvdt::Role::Date: return "Date";
                case csvdt::Role::Time: return "Time";
                case csvdt::Role::DateTime: return "DateTime";
                case csvdt::Role::EpochSeconds: return "EpochSeconds";
                case csvdt::Role::EpochMillis: return "EpochMillis";
                default: return "Unknown";
            }
        };
        for (auto &d : res.all_columns) {
            std::cout << "  ["<<d.index<<"] header='"<<d.header<<"' role="<<role_to_str(d.role)
                      << " conf="<<std::fixed<<std::setprecision(2)<<d.confidence
                      << (d.format.empty() ? "" : (" fmt='" + d.format + "'"))
                      << "\n";
        }

        std::cout << "\nBest mapping:\n";
        if (res.datetime_col) {
            auto &d = *res.datetime_col;
            std::cout << "  DateTime column: #" << d.index << " ('" << d.header << "')";
            if (d.role==csvdt::Role::EpochSeconds || d.role==csvdt::Role::EpochMillis) {
                std::cout << " [epoch]\n";
            } else {
                std::cout << " fmt='" << d.format << "'\n";
            }
        } else {
            if (res.date_col) {
                auto &d = *res.date_col;
                std::cout << "  Date column:    #" << d.index << " ('" << d.header << "') fmt='" << d.format << "'\n";
            }
            if (res.time_col) {
                auto &d = *res.time_col;
                std::cout << "  Time column:    #" << d.index << " ('" << d.header << "') fmt='" << d.format << "'\n";
            }
            if (!res.date_col && !res.time_col) {
                std::cout << "  (No confident date/time mapping found.)\n";
            }
        }
    } catch (const std::exception &e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 2;
    }
    return 0;
}
#endif
