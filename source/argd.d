module argd;

import std.stdio;
import std.array;
import std.conv;
import std.algorithm;
import std.string;
import std.format;

enum ArgCollectionType { exact, minimum, any }

struct Option {
    string longName;
    string shortName;
    string description;
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

protected:
    Command[string] subCommands;
    string[] options;
    Option[] registeredOptions;

    bool hasOption(string longName, string shortName = "") {
        return options.canFind(longName) || (shortName.length > 0 && options.canFind(shortName));
    }


public:
    this(string name, bool withHelp = true) {
        this.name = name;
        if (withHelp)
            registerSubCommand(new HelpSubCommand(this));
    }

    void registerSubCommand(Command cmd) {
        subCommands[cmd.name] = cmd;
    }

    void addOption(string longName, string shortName, string description) {
        registeredOptions ~= Option(longName, shortName, description);
    }

    final CommandResult handle(string[] inputArgs, string[] globalOpts = []) {
        string[] args;
        string[] opts;

        foreach (arg; inputArgs) {
            if (parseOptions && arg.length > 0 && arg[0] == '-') opts ~= arg;
            else args ~= arg;
        }

        this.options = opts ~ globalOpts;

        if (args.length > 0) {
            auto sub = args[0];
            if (sub in subCommands)
                return subCommands[sub].handle(args[1 .. $], this.options);
        }

        if (hasOption("--help", "-h"))
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
        }
    }


    string buildHelp() {
        string out_;
        out_ ~= "Usage: " ~ (name.length > 0 ? name ~ " " : "") ~ usage ~ "\n\n";
        out_ ~= description ~ "\n\n";

        if (subCommands.length > 1) {
            out_ ~= "Subcommands:\n";
            foreach (cmd; subCommands) {
                if (cmd.name != "--help")
                    out_ ~= format("  %-20s %s\n", cmd.name, cmd.description);
            }
            out_ ~= "\n";
        }

        out_ ~= "Options:\n";
        out_ ~= format("  %-20s %s\n", "-h, --help", "Show this help message");
        foreach (opt; registeredOptions) {
            string flags = opt.longName;
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
        out_ ~= "| `-h, --help` | Show this help message |\n";
        foreach (opt; registeredOptions) {
            string flags = opt.longName;
            if (opt.shortName.length > 0) flags = opt.shortName ~ ", " ~ flags;
            out_ ~= "| `" ~ flags ~ "` | " ~ opt.description ~ " |\n";
        }
        out_ ~= "\n";

        if (subCommands.length > 1) {
            out_ ~= h ~ "# Subcommands\n\n";
            foreach (cmdName, cmd; subCommands) {
                if (cmd.name != "--help") {
                    out_ ~= cmd.buildMarkdown(depth + 1);
                }
            }
        }
        
        return out_;
    }

    protected abstract CommandResult onExecute(string[] args, bool verbose, bool quiet);
}

class HelpSubCommand : Command {
    private Command parent;
    this(Command parent) {
        super("--help", false);
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

// ----------------------------------------------------------------------------
// Unit Tests
// ----------------------------------------------------------------------------

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