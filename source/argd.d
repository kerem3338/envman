/**
Argd

Argument parser/command system for the D Programming Language

License: MIT

Licensed under the MIT License

2026 © Kerem ATA (zoda)
*/
module argd;

import std.stdio;
import std.array;
import std.conv;
import std.algorithm;
import std.string;
import std.format;

enum ArgCollectionType { exact, minimum, any, none, below, above }

struct Option {
    string longName;
    string shortName;
    string description;
    string valueName = "";
}


struct CommandResult {
    bool success;
    string message;
    int exitCode = 0;

    static CommandResult ok(string message = "") { return CommandResult(true, message, 0); }
    static CommandResult error(string message, int exitCode = 1) { return CommandResult(false, message, exitCode); }
}


class Command {
    string name;
    string description = "No description";
    string usage = "[options]";
    ArgCollectionType argCollType = ArgCollectionType.any;
    int argCount = 0;
    bool parseOptions = true;
    string helpLongName = "--help";
    string helpShortName = "-h";

protected:
    Command[string] subCommands;
    string[] options;
    string[string] optionValues;
    Option[] registeredOptions;

    private string norm(string name) {
        if (name.startsWith("--")) return name[2..$];
        if (name.startsWith("-")) return name[1..$];
        return name;
    }

    bool hasOption(string longName, string shortName = "") {
        string nL = norm(longName);
        string nS = shortName.length > 0 ? norm(shortName) : "";
        foreach (opt; options) {
            string nO = norm(opt);
            if (nO == nL || (nS.length > 0 && nO == nS)) return true;
        }
        return false;
    }

    string getOption(string longName, string shortName = "", string defaultValue = "") {
        string nL = norm(longName);
        string nS = shortName.length > 0 ? norm(shortName) : "";
        foreach (k, v; optionValues) {
            string nK = norm(k);
            if (nK == nL || (nS.length > 0 && nK == nS)) return v;
        }
        return defaultValue;
    }


public:
    this(string name, bool withHelp = true) {
        this.name = name;
        if (withHelp)
            registerSubCommand(new HelpSubCommand(this, helpLongName, helpShortName));
    }

    void registerSubCommand(Command cmd) {
        subCommands[cmd.name] = cmd;
    }

    void addOption(string longName, string shortName, string description, string valueName = "") {
        registeredOptions ~= Option(longName, shortName, description, valueName);
    }

    final CommandResult handle(string[] inputArgs, string[] globalOpts = [], string[string] inheritedValues = null) {
        string[] args;       // all positional args
        string[] preEndArgs; // positional args before --
        string[] postEndArgs;// positional args after --
        string[] opts;
        string[string] values;

        bool isOptionWithValue(string name) {
            string n = norm(name);
            foreach (opt; registeredOptions) {
                if (norm(opt.longName) == n || (opt.shortName.length > 0 && norm(opt.shortName) == n))
                    return opt.valueName.length > 0;
            }
            return false;
        }

        bool isRegistered(string name) {
            string n = norm(name);
            if (n == norm(helpLongName) || (helpShortName.length > 0 && n == norm(helpShortName))) {
                return (helpLongName in subCommands) !is null;
            }
            foreach (opt; registeredOptions) {
                if (norm(opt.longName) == n || (opt.shortName.length > 0 && norm(opt.shortName) == n))
                    return true;
            }
            return false;
        }

        bool endOfOptions = false;
        for (int i = 0; i < inputArgs.length; i++) {
            string arg = inputArgs[i];
            
            if (!endOfOptions && arg == "--") { 
                endOfOptions = true; 
                continue; 
            }
            
            if (!endOfOptions && parseOptions && arg.length > 1 && arg[0] == '-') {
                auto eqIdx = arg.indexOf('=');
                if (eqIdx > 0) {
                    string key = arg[0 .. eqIdx];
                    string val = arg[eqIdx + 1 .. $];
                    opts ~= key;
                    values[key] = val;
                } else if (arg.startsWith("--")) {
                    opts ~= arg;
                    if (isOptionWithValue(arg) && i + 1 < inputArgs.length) {
                        values[arg] = inputArgs[i + 1];
                        i++;
                    }
                } else {
                    if (isRegistered(arg)) {
                        opts ~= arg;
                        if (isOptionWithValue(arg) && i + 1 < inputArgs.length) {
                            values[arg] = inputArgs[i + 1];
                            i++;
                        }
                    } else if (arg.length > 2) {
                        foreach (char c; arg[1 .. $]) {
                            string bundled = "-" ~ c;
                            opts ~= bundled;
                        }
                    } else {
                        opts ~= arg;
                        if (isOptionWithValue(arg) && i + 1 < inputArgs.length) {
                            values[arg] = inputArgs[i + 1];
                            i++;
                        }
                    }
                }
            } else {
                if (!endOfOptions && preEndArgs.length == 0 && (arg in subCommands)) {
                    this.options = opts ~ globalOpts;
                    if (inheritedValues !is null)
                        foreach (k, v; inheritedValues) { if (k !in values) values[k] = v; }
                    this.optionValues = values;
                    return subCommands[arg].handle(inputArgs[i + 1 .. $], this.options, this.optionValues);
                }

                args ~= arg;
                if (!endOfOptions) preEndArgs ~= arg;
                else postEndArgs ~= arg;
            }
        }

        this.options = opts ~ globalOpts;
        if (inheritedValues !is null)
            foreach (k, v; inheritedValues) { if (k !in values) values[k] = v; }
        this.optionValues = values;

        if (hasOption(helpLongName, helpShortName) && (helpLongName in subCommands) !is null)
            return CommandResult.ok(buildHelp());


        if (!validateArgs(args))
            return CommandResult.error("Invalid arguments. Expected " ~
                argCount.to!string ~ " but got " ~ args.length.to!string ~
                "\n\n" ~ buildHelp());

        bool verbose = hasOption("--verbose", "-v");
        bool quiet = hasOption("--quiet", "-q");

        return onExecute(args, verbose, quiet);
    }

protected:
    bool validateArgs(string[] args) {
        final switch (argCollType) {
            case ArgCollectionType.exact: return args.length == argCount;
            case ArgCollectionType.minimum: return args.length >= argCount;
            case ArgCollectionType.any: return true;
            case ArgCollectionType.none: return args.length == 0;
            case ArgCollectionType.below: return args.length < argCount;
            case ArgCollectionType.above: return args.length > argCount;
        }
    }


    string buildHelp() {
        string out_;
        out_ ~= "Usage: " ~ (name.length > 0 ? name ~ " " : "") ~ usage ~ "\n\n";
        out_ ~= description ~ "\n\n";

        if (subCommands.length > 1) {
            out_ ~= "Subcommands:\n";
            foreach (cmd; subCommands) {
                if (cmd.name != helpLongName)
                    out_ ~= format("  %-20s %s\n", cmd.name, cmd.description);
            }
            out_ ~= "\n";
        }

        out_ ~= "Options:\n";
        out_ ~= format("  %-20s %s\n", helpShortName ~ ", " ~ helpLongName, "Show this help message");
        foreach (opt; registeredOptions) {
            string flags = opt.longName;
            if (opt.valueName.length > 0) flags ~= "=<" ~ opt.valueName ~ ">";
            if (opt.shortName.length > 0)
                flags = opt.shortName ~ ", " ~ flags;
            out_ ~= format("  %-20s %s\n", flags, opt.description);
        }
        return out_;
    }

    string buildMarkdown(int depth = 1) {
        string h = "";
        foreach (i; 0 .. depth) h ~= "#";
        
        string out_;
        out_ ~= h ~ " `" ~ (name.length > 0 ? name : "Command") ~ "`\n\n";
        out_ ~= description ~ "\n\n";
        
        out_ ~= "**Usage:** `" ~ (name.length > 0 ? name ~ " " : "") ~ usage ~ "`\n\n";

        bool hasOpts = registeredOptions.length > 0;
        out_ ~= h ~ "# Options\n\n";
        out_ ~= "| Option | Description |\n";
        out_ ~= "|--------|-------------|\n";
        out_ ~= "| `" ~ helpShortName ~ ", " ~ helpLongName ~ "` | Show this help message |\n";
        foreach (opt; registeredOptions) {
            string flags = opt.longName;
            if (opt.valueName.length > 0) flags ~= "=&lt;" ~ opt.valueName ~ "&gt;";
            if (opt.shortName.length > 0) flags = opt.shortName ~ ", " ~ flags;
            out_ ~= "| `" ~ flags ~ "` | " ~ opt.description ~ " |\n";
        }
        out_ ~= "\n";

        if (subCommands.length > 1) {
            out_ ~= h ~ "# Subcommands\n\n";
            foreach (cmdName, cmd; subCommands) {
                if (cmd.name != helpLongName) {
                    out_ ~= cmd.buildMarkdown(depth + 1);
                }
            }
        }
        
        return out_;
    }

    private string escapeHTML(string s) {
        return s.replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&apos;");
    }

    string buildHTML(bool fullPage = true) {
        return buildHTMLInner(fullPage, 1);
    }

    private string buildHTMLInner(bool fullPage, int depth) {
        string html;

        if (fullPage) {
            html ~= "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n";
            html ~= "    <meta charset=\"UTF-8\">\n";
            html ~= "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n";
            html ~= "    <title>Documentation - " ~ escapeHTML(name.length > 0 ? name : "App") ~ "</title>\n";
            html ~= "    <style>\n";
            html ~= "        :root { --bg: #0f172a; --card: #1e293b; --text: #f8fafc; --accent: #38bdf8; --dim: #94a3b8; }\n";
            html ~= "        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: var(--bg); color: var(--text); line-height: 1.6; margin: 0; padding: 2rem; }\n";
            html ~= "        .container { max-width: 900px; margin: 0 auto; }\n";
            html ~= "        .command-card { background: var(--card); padding: 1.5rem; border-radius: 12px; margin-bottom: 1.5rem; border-left: 4px solid var(--accent); box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.3); }\n";
            html ~= "        .command-card.sub { border-left-color: var(--dim); background: #162032; }\n";
            html ~= "        h1, h2, h3, h4 { color: var(--accent); margin-top: 0; }\n";
            html ~= "        h2 { color: #7dd3fc; }\n";
            html ~= "        h3, h4 { color: var(--dim); }\n";
            html ~= "        code { background: #000; padding: 0.2rem 0.4rem; border-radius: 4px; font-family: monospace; color: #ef4444; }\n";
            html ~= "        .usage { background: #000; padding: 1rem; border-radius: 8px; font-family: monospace; overflow-x: auto; margin: 1rem 0; border: 1px solid #334155; }\n";
            html ~= "        table { width: 100%; border-collapse: collapse; margin-block: 1rem; }\n";
            html ~= "        th { text-align: left; border-bottom: 2px solid var(--dim); padding: 0.5rem; color: var(--accent); }\n";
            html ~= "        td { padding: 0.5rem; border-bottom: 1px solid #334155; }\n";
            html ~= "        .subcommands { margin-left: 1.5rem; border-left: 2px dashed #334155; padding-left: 1.5rem; margin-top: 1rem; }\n";
            html ~= "    </style>\n</head>\n<body>\n<div class=\"container\">\n";
        }

        string hn(int d) {
            import std.algorithm : min;
            int lvl = min(d, 4);
            import std.conv : to;
            return "h" ~ lvl.to!string;
        }

        string cardClass = depth == 1 ? "command-card" : "command-card sub";
        string h = hn(depth);

        html ~= "<div class=\"" ~ cardClass ~ "\">\n";
        html ~= "  <" ~ h ~ ">" ~ escapeHTML(name.length > 0 ? name : "Command") ~ "</" ~ h ~ ">\n";
        html ~= "  <p>" ~ escapeHTML(description) ~ "</p>\n";
        html ~= "  <div class=\"usage\"><strong>Usage:</strong> "
              ~ escapeHTML((name.length > 0 ? name ~ " " : "") ~ usage)
              ~ "</div>\n";

        bool hasOpts = registeredOptions.length > 0;
        if (hasOpts) {
            string oh = hn(depth + 1);
            html ~= "  <" ~ oh ~ ">Options</" ~ oh ~ ">\n";
            html ~= "  <table>\n";
            html ~= "    <tr><th>Flag</th><th>Description</th></tr>\n";
            html ~= "    <tr><td><code>" ~ escapeHTML(helpShortName ~ ", " ~ helpLongName) ~ "</code></td><td>Show this help message</td></tr>\n";
            foreach (opt; registeredOptions) {
                string flags = opt.longName;
                if (opt.valueName.length > 0) flags ~= "=<" ~ opt.valueName ~ ">";
                if (opt.shortName.length > 0) flags = opt.shortName ~ ", " ~ flags;
                html ~= format("    <tr><td><code>%s</code></td><td>%s</td></tr>\n",
                    escapeHTML(flags), escapeHTML(opt.description));
            }
            html ~= "  </table>\n";
        }

        html ~= "</div>\n";

        bool hasSubs = false;
        foreach (cmdName, cmd; subCommands)
            if (cmd.name != helpLongName) { hasSubs = true; break; }

        if (hasSubs) {
            html ~= "<div class=\"subcommands\">\n";
            foreach (cmdName, cmd; subCommands) {
                if (cmd.name != helpLongName)
                    html ~= cmd.buildHTMLInner(false, depth + 1);
            }
            html ~= "</div>\n";
        }

        if (fullPage)
            html ~= "</div>\n</body>\n</html>";

        return html;
    }

    protected abstract CommandResult onExecute(string[] args, bool verbose, bool quiet);
}

class HelpSubCommand : Command {
    private Command parent;
    this(Command parent, string longName, string shortName) {
        super(longName, false);
        this.parent = parent;
        description = "Show help for " ~ parent.name;
    }

    override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
        return CommandResult.ok(parent.buildHelp());
    }
}

string[] parseArgs(string cmd) {
    string[] result;
    string buf;
    bool inQuotes = false;

    foreach (c; cmd) {
        if (c == '"') {
            inQuotes = !inQuotes;
            continue;
        }
        if (c == ' ' && !inQuotes) {
            if (buf.length > 0) {
                result ~= buf;
                buf = "";
            }
        } else {
            buf ~= c;
        }
    }
    if (buf.length > 0)
        result ~= buf;
    return result;
}

unittest {
    import std.algorithm.searching : canFind;

    auto res = CommandResult.ok("Success");
    assert(res.success == true);
    assert(res.message == "Success");

    auto err = CommandResult.error("Failed", 2);
    assert(err.success == false);
    assert(err.message == "Failed");
    assert(err.exitCode == 2);

    class MockCmd : Command {
        this() { super("mock"); }
        override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) { return CommandResult.ok(); }
    }
    auto cmd = new MockCmd();
    cmd.options = ["--verbose", "-v", "--force"];
    
    assert(cmd.hasOption("--verbose"));
    assert(cmd.hasOption("--force"));
    assert(cmd.hasOption("", "-v"));
    assert(cmd.hasOption("--verbose", "-v"));
    assert(!cmd.hasOption("--quiet"));
    assert(!cmd.hasOption("", "-q"));

    cmd.argCollType = ArgCollectionType.exact;
    cmd.argCount = 2;
    assert(cmd.validateArgs(["a", "b"]));
    assert(!cmd.validateArgs(["a"]));
    assert(!cmd.validateArgs(["a", "b", "c"]));

    cmd.argCollType = ArgCollectionType.minimum;
    cmd.argCount = 1;
    assert(cmd.validateArgs(["a"]));
    assert(cmd.validateArgs(["a", "b"]));
    assert(!cmd.validateArgs([]));

    cmd.argCollType = ArgCollectionType.any;
    assert(cmd.validateArgs([]));
    assert(cmd.validateArgs(["a", "b", "c"]));

    cmd.argCollType = ArgCollectionType.none;
    assert(cmd.validateArgs([]));
    assert(!cmd.validateArgs(["a"]));

    cmd.argCollType = ArgCollectionType.below;
    cmd.argCount = 3;
    assert(cmd.validateArgs(["a", "b"]));
    assert(!cmd.validateArgs(["a", "b", "c"]));
    assert(!cmd.validateArgs(["a", "b", "c", "d"]));

    cmd.argCollType = ArgCollectionType.above;
    cmd.argCount = 1;
    assert(cmd.validateArgs(["a", "b"]));
    assert(!cmd.validateArgs(["a"]));
    assert(!cmd.validateArgs([]));

    class SubCmd : Command {
        this() { super("sub"); }
        override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
            return CommandResult.ok("sub_executed");
        }
    }

    auto root = new class Command {
        this() { super("root"); }
        override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
            return CommandResult.ok("root_executed");
        }
    };
    root.registerSubCommand(new SubCmd());

    auto res1 = root.handle([]);
    assert(res1.success);
    assert(res1.message == "root_executed");

    auto res2 = root.handle(["sub"]);
    assert(res2.success);
    assert(res2.message == "sub_executed");

    auto res3 = root.handle(["--help"]);
    assert(res3.success);
    assert(res3.message.canFind("Usage: root"));
    assert(res3.message.canFind("sub"));
}

// --key=value parsing and getOption()
unittest {
    string capturedOutput;
    string capturedCount;

    class ValueCmd : Command {
        this() {
            super("vcmd");
            argCollType = ArgCollectionType.any;
            addOption("--output", "-o", "Output file");
            addOption("--count",  "-n", "Item count");
        }
        override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
            capturedOutput = getOption("--output", "-o", "default.txt");
            capturedCount  = getOption("--count",  "-n", "0");
            return CommandResult.ok();
        }
    }

    auto vcmd = new ValueCmd();

    // --key=value long form
    capturedOutput = "";
    vcmd.handle(["--output=result.txt"]);
    assert(capturedOutput == "result.txt");

    // short form -k=value
    capturedOutput = "";
    vcmd.handle(["-o=out.d"]);
    assert(capturedOutput == "out.d");

    // multiple key=value pairs
    capturedOutput = ""; capturedCount = "";
    vcmd.handle(["--output=foo.txt", "--count=42"]);
    assert(capturedOutput == "foo.txt");
    assert(capturedCount  == "42");

    // hasOption still works for --key=value
    vcmd.handle(["--output=x.txt"]);
    assert(vcmd.hasOption("--output", "-o"));
    assert(!vcmd.hasOption("--count", "-n"));

    // default returned when option absent
    capturedOutput = "";
    vcmd.handle([]);
    assert(capturedOutput == "default.txt");

    // plain flag (no =value) → hasOption true, getOption returns default
    capturedCount = "";
    vcmd.handle(["--count"]);
    assert(vcmd.hasOption("--count", "-n"));
    assert(capturedCount == "0");
}

// -- end-of-options sentinel
unittest {
    string[] capturedArgs;

    class SentinelCmd : Command {
        this() {
            super("scmd");
            argCollType = ArgCollectionType.any;
        }
        override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
            capturedArgs = args;
            return CommandResult.ok();
        }
    }

    auto scmd = new SentinelCmd();

    // Without --, "-cfg" is consumed as an option → args is empty
    capturedArgs = null;
    scmd.handle(["-cfg"]);
    assert(capturedArgs.length == 0);

    // With --, "-cfg" is treated as a positional arg
    capturedArgs = null;
    scmd.handle(["--", "-cfg"]);
    assert(capturedArgs.length == 1);
    assert(capturedArgs[0] == "-cfg");

    // Everything after -- is positional, even if it looks like a flag
    capturedArgs = null;
    scmd.handle(["--", "--foo", "-bar", "baz"]);
    assert(capturedArgs == ["--foo", "-bar", "baz"]);

    // Args before -- still split normally
    capturedArgs = null;
    scmd.handle(["hello", "--", "-x"]);
    assert(capturedArgs == ["hello", "-x"]);
}

// --key=value inherited by subcommands
unittest {
    string subCaptured;

    class InheritSub : Command {
        this() {
            super("child");
            argCollType = ArgCollectionType.any;
            addOption("--mode", "-m", "Mode");
        }
        override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
            subCaptured = getOption("--mode", "-m", "none");
            return CommandResult.ok();
        }
    }

    auto parentCmd = new class Command {
        this() {
            super("parent");
            argCollType = ArgCollectionType.any;
            addOption("--mode", "-m", "Mode");
            registerSubCommand(new InheritSub());
        }
        override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
            return CommandResult.ok();
        }
    };

    // Value set at parent level propagates to child
    subCaptured = "";
    parentCmd.handle(["--mode=fast", "child"]);
    assert(subCaptured == "fast");

    // Child's own value overrides parent's
    subCaptured = "";
    parentCmd.handle(["--mode=slow", "child", "--mode=turbo"]);
    assert(subCaptured == "turbo");
}

// Space-separated values and Bundling
unittest {
    string outVal;
    bool flagA, flagB, flagC;

    class MultiCmd : Command {
        this() {
            super("mcmd");
            argCollType = ArgCollectionType.any;
            addOption("--output", "-o", "Output file", "file");
            addOption("--apple",  "-a", "Flag A");
            addOption("-b",       "",   "Flag B");
            addOption("-c",       "",   "Flag C");
        }
        override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
            outVal = getOption("--output", "-o");
            flagA = hasOption("--apple", "-a");
            flagB = hasOption("-b");
            flagC = hasOption("-c");
            return CommandResult.ok();
        }
    }

    auto cmd = new MultiCmd();

    // Space-separated value
    outVal = "";
    cmd.handle(["--output", "test.txt"]);
    assert(outVal == "test.txt");

    // Space-separated with short flag
    outVal = "";
    cmd.handle(["-o", "short.txt"]);
    assert(outVal == "short.txt");

    // Bundled flags
    flagA = flagB = flagC = false;
    cmd.handle(["-abc"]);
    assert(flagA && flagB && flagC);

    // Mixed bundling and space-separated
    flagA = flagB = flagC = false; outVal = "";
    cmd.handle(["-ab", "--output", "mixed.txt", "-c"]);
    assert(flagA && flagB && flagC);
    assert(outVal == "mixed.txt");

    // Multi-character short option priority
    class PriorityCmd : Command {
        this() {
            super("pcmd");
            addOption("--path-dir", "-pd", "Combined path and dir");
            addOption("--path", "-p", "Path only");
            addOption("--dir", "-d", "Dir only");
        }
        override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) { return CommandResult.ok(); }
    }
    auto pcmd = new PriorityCmd();
    pcmd.handle(["-pd"]);
    assert(pcmd.hasOption("--path-dir", "-pd"));
    assert(!pcmd.hasOption("--path", "-p"));
    assert(!pcmd.hasOption("--dir", "-d"));

    // Disabled help with custom -h
    class NoHelpCmd : Command {
        this() {
            super("nohelp", false); // withHelp = false
            addOption("--hide", "-h", "Hide thing");
        }
        override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) { return CommandResult.ok("executed"); }
    }
    auto nhcmd = new NoHelpCmd();
    auto resH = nhcmd.handle(["-h"]);
    assert(resH.success);
    assert(resH.message == "executed"); // Should NOT show help
    assert(nhcmd.hasOption("--hide", "-h"));

    // Custom help flags
    class CustomHelpCmd : Command {
        this() { 
            helpLongName = "--assistance";
            helpShortName = "-a";
            super("acmd"); 
        }
        override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) { return CommandResult.ok("exec"); }
    }
    auto acmd = new CustomHelpCmd();
    auto resA = acmd.handle(["-a"]);
    assert(resA.success);
    assert(resA.message.canFind("Usage: acmd"));
    assert(acmd.buildHelp().canFind("-a, --assistance"));
}

// Documentation unittests
unittest {
    import std.algorithm.searching : canFind;

    auto root = new class Command {
        this() {
            super("myapp");
            addOption("--output", "-o", "Set output", "file");
            addOption("--verbose", "-v", "Verbose mode");
        }
        override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
            return CommandResult.ok();
        }
    };

    // Text help
    auto help = root.buildHelp();
    assert(help.canFind("--output=<file>"));

    // Markdown
    auto md = root.buildMarkdown();
    assert(md.canFind("--output=&lt;file&gt;"));

    // HTML
    auto html = root.buildHTML();
    assert(html.canFind("--output=&lt;file&gt;"));
}

// Subcommand multi-character option splitting fix
unittest {
    class SubWithMulti : Command {
        this() {
            super("sub");
            addOption("--list-ignored", "-li", "Test");
        }
        override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
            if (hasOption("--list-ignored", "-li")) return CommandResult.ok("multi_found");
            return CommandResult.error("multi_not_found");
        }
    }

    auto root = new class Command {
        this() {
            super("root");
            registerSubCommand(new SubWithMulti());
        }
        override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
            return CommandResult.ok("root");
        }
    };

    // Before fix, "-li" would be split into "-l" and "-i" by Root, then Sub gets ["-l", "-i"]
    // After fix, Root stops at "sub", Sub parses "-li" and finds it registered.
    auto res = root.handle(["sub", "-li"]);
    assert(res.success);
    assert(res.message == "multi_found");
}