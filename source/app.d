/**
envman

Environment manager for your needs.

Licensed under The MIT License
**/
import std.stdio;
import std.getopt;
import std.file;
import std.path;
import std.datetime;
import std.conv;
import std.array;
import std.algorithm;
import std.format;
import core.stdc.stdlib;
import std.string;
import std.array;
import std.algorithm.mutation;
import std.process;
import std.typecons;
import std.utf : toUTF16z;
import std.regex : regex, replaceAll;

version(Windows) {
	import core.sys.windows.windows;
	import core.sys.windows.winbase;

	extern(Windows) BOOL CreateSymbolicLinkW(LPCWSTR lpSymlinkFileName, LPCWSTR lpTargetFileName, DWORD dwFlags);
}

import consolecolors;
import toml;
import argd;

const string COMPILED_AT = __TIMESTAMP__;
const Version ENVMAN_VERSION = Version(0,0,2);
const string PROJECT_FILE = "project.envman";
const string LEGACY_PACKAGES_FILE = "packages.envman";
__gshared Instance instance;

struct Version {
	int major;
	int minor;
	int patch;

	this(int major, int minor, int patch) {
		this.major = major;
		this.minor = minor;
		this.patch = patch;
	}

	static Version fromString(string s) {
		auto parts = s.split(".");

		Version v;
		if (parts.length > 0) v.major = parts[0].to!int;
		if (parts.length > 1) v.minor = parts[1].to!int;
		if (parts.length > 2) v.patch = parts[2].to!int;

		return v; 
	}

	string toString() const {
		return format("%d.%d.%d",major,minor,patch);
	}
} 

struct PackageConfig {
	string aliasName;
	string dest;
	string expectedType;
	string description;
	string obtainFrom;
}

struct Project {
	string name;
	string version_;
	string description;
	string[] authors;
	string license;
	string homepage;
	string repository;
	string[] keywords;
	Version envmanVersion;
}

struct Package {
	string name;
	string path;
	string pathKind;
	TOMLValue[string] metadata;
	string[] tags;

	bool hasTag(string tag) const {
		foreach (t; tags) if (t == tag) return true;
		return false;
	}
}

enum ConfigKey : string {
	editor = "editor",
	shell = "shell"
}

class OneFileManager {
	Instance instance;
	
	this(Instance instance) {
		this.instance = instance;
	}

	bool isPackageExists(string pkgAlias) {
		auto packages = instance.getPackagesTable();
		return (pkgAlias in packages) !is null;
	}

	Tuple!(bool, Package) getPackage(string pkgAlias) {
		auto packages = instance.getPackagesTable();
		if (auto pVal = pkgAlias in packages) {
			return tuple(true, packageFromTOML(pkgAlias, *pVal));
		}
		return tuple(false, Package.init);
	}

	Package[] getAllPackages() {
		Package[] list;
		auto packages = instance.getPackagesTable();
		foreach (pkgAlias, val; packages) {
			list ~= packageFromTOML(pkgAlias, val);
		}
		return list;
	}

	bool registerPackage(Package pkg) {
		instance.updatePackagesTable((ref packages) {
			TOMLValue[string] tbl;
			tbl["path"] = TOMLValue(pkg.path);
			if (pkg.tags.length > 0) {
				TOMLValue[] tagArray;
				foreach(t; pkg.tags) tagArray ~= TOMLValue(t);
				tbl["tags"] = TOMLValue(tagArray);
			}
			foreach(k, v; pkg.metadata) tbl[k] = v;
			
			packages[pkg.name] = TOMLValue(tbl);
		});
		return true;
	}

	bool registerPackage(string name, string path) {
		instance.updatePackagesTable((ref packages) {
			packages[name] = TOMLValue(path);
		});
		return true;
	}

	bool removePackage(string pkgAlias) {
		bool removed = false;
		instance.updatePackagesTable((ref packages) {
			if ((pkgAlias in packages) !is null) {
				packages.remove(pkgAlias);
				removed = true;
			}
		});
		return removed;
	}

	bool registerFromFile(string filePath, out Package pkg) {
		if (!filePath.endsWith(".envman.package")) return false;
		pkg = parsePackageFile(filePath);
		return registerPackage(pkg);
	}

	Package getPackageOrFail(string pkgAlias) {
		auto res = getPackage(pkgAlias);
		if (!res[0]) throw new Exception("Package '" ~ pkgAlias ~ "' not found in the global registry.");
		return res[1];
	}
}

class ProjectFileManager {
	string filePath;
	string fileName = PROJECT_FILE;

	this(string dir = ".") {
		filePath = buildPath(dir, fileName);
	}

	bool exists() const {
		return std.file.exists(filePath);
	}

	bool init(Project pj = Project.init) {
		if (exists()) return false;
		
		TOMLDocument doc;
		TOMLValue[string] pTbl;
		pTbl["name"] = TOMLValue(pj.name);
		pTbl["version"] = TOMLValue(pj.version_);
		pTbl["description"] = TOMLValue(pj.description);
		
		TOMLValue[] authors;
		foreach(a; pj.authors) authors ~= TOMLValue(a);
		pTbl["authors"] = TOMLValue(authors);
		
		pTbl["license"] = TOMLValue(pj.license);
		pTbl["homepage"] = TOMLValue(pj.homepage);
		pTbl["repository"] = TOMLValue(pj.repository);
		
		TOMLValue[] keywords;
		foreach(k; pj.keywords) keywords ~= TOMLValue(k);
		pTbl["keywords"] = TOMLValue(keywords);
		
		pTbl["envman_version"] = TOMLValue(ENVMAN_VERSION.toString());

		doc["project"] = TOMLValue(pTbl);
		doc["packages"] = TOMLValue(new TOMLValue[string]);

		save(doc);
		return true;
	}

	Project getProject() {
		Project pj;
		pj.name = "Unknown";
		pj.version_ = "Unknown";
		pj.description = "Unknown";
		pj.license = "Unknown";
		pj.homepage = "Unknown";
		pj.repository = "Unknown";
		pj.envmanVersion = ENVMAN_VERSION;

		auto doc = load();
		if ("project" in doc && doc["project"].type == TOML_TYPE.TABLE) {
			auto tbl = doc["project"].table;
			if ("name" in tbl) pj.name = tbl["name"].str;
			if ("version" in tbl) pj.version_ = tbl["version"].str;
			if ("description" in tbl) pj.description = tbl["description"].str;
			pj.authors = extractStringArray(tbl, "authors");
			if ("license" in tbl) pj.license = tbl["license"].str;
			if ("homepage" in tbl) pj.homepage = tbl["homepage"].str;
			if ("repository" in tbl) pj.repository = tbl["repository"].str;
			pj.keywords = extractStringArray(tbl, "keywords");
			if ("envman_version" in tbl) pj.envmanVersion = Version.fromString(tbl["envman_version"].str);
		}
		return pj;
	}

	PackageConfig[] getPackagesConfig(bool quiet, out bool success, out string errorMsg) {
		if (!exists()) {
			success = false;
			errorMsg = "No " ~ fileName ~ " found.";
			return null;
		}

		auto doc = load();
		if ("packages" !in doc || doc["packages"].type != TOML_TYPE.TABLE) {
			success = false;
			errorMsg = "No valid [packages] table found in " ~ filePath;
			return null;
		}

		PackageConfig[] configs;
		auto projectPackages = doc["packages"].table;

		foreach(pkgAlias, destNode; projectPackages) {
			string dest = "";
			string expectedType = "any";
			string description = "";
			string obtainFrom = "";

			if (destNode.type == TOML_TYPE.STRING) {
				dest = destNode.str;
			} else if (destNode.type == TOML_TYPE.ARRAY) {
				dest = buildPathFromTOMLArray(destNode);
			} else if (destNode.type == TOML_TYPE.TABLE) {
				auto tbl = destNode.table;
				if ("path" in tbl) {
					if (tbl["path"].type == TOML_TYPE.STRING) {
						dest = tbl["path"].str;
					} else if (tbl["path"].type == TOML_TYPE.ARRAY) {
						dest = buildPathFromTOMLArray(tbl["path"]);
					}
				}
				if ("type" in tbl && tbl["type"].type == TOML_TYPE.STRING) {
					expectedType = tbl["type"].str;
				}
				if ("description" in tbl && tbl["description"].type == TOML_TYPE.STRING) {
					description = tbl["description"].str;
				}
				if ("obtain" in tbl && tbl["obtain"].type == TOML_TYPE.STRING) {
					obtainFrom = tbl["obtain"].str;
				}
			}

			if (dest.length == 0) {
				if (!quiet) writeln("Skipping package ", pkgAlias, ": invalid destination format");
				continue;
			}
			configs ~= PackageConfig(pkgAlias, dest, expectedType, description, obtainFrom);
		}
		success = true;
		return configs;
	}

	private TOMLDocument load() {
		if (!std.file.exists(filePath))
			return parseTOML("");
		return parseTOML(readText(filePath));
	}

	private void save(ref TOMLDocument doc) {
		auto buffer = appender!string();
		writeTomlTable(doc, buffer);
		std.file.write(filePath, buffer.data);
	}

	private TOMLValue[string] getTable(ref TOMLDocument doc) {
		if ("packages" !in doc) {
			TOMLValue[string] empty;
			doc["packages"] = TOMLValue(empty);
		}
		if (doc["packages"].type != TOML_TYPE.TABLE)
			throw new Exception("Existing " ~ fileName ~ " has an invalid [packages] section. Must be a table.");
		return doc["packages"].table;
	}

	void updatePackages(void delegate(ref TOMLValue[string]) @safe updater) {
		auto doc = load();
		auto tbl = getTable(doc);
		updater(tbl);
		doc["packages"] = TOMLValue(tbl);
		save(doc);
	}

	bool hasEntry(string aliasName) {
		auto doc = load();
		if ("packages" !in doc || doc["packages"].type != TOML_TYPE.TABLE)
			return false;
		return (aliasName in doc["packages"].table) !is null;
	}

	void addEntry(string aliasName, string destination) {
		if (!std.file.exists(filePath))
			std.file.write(filePath, "");
		updatePackages((ref tbl) { tbl[aliasName] = TOMLValue(destination); });
	}

	bool removeEntry(string aliasName) {
		if (!std.file.exists(filePath)) return false;
		bool removed = false;
		updatePackages((ref tbl) {
			if ((aliasName in tbl) !is null) {
				tbl.remove(aliasName);
				removed = true;
			}
		});
		return removed;
	}

	void removeEntries(string[] aliases) {
		if (!std.file.exists(filePath) || aliases.length == 0) return;
		updatePackages((ref tbl) {
			foreach (a; aliases) tbl.remove(a);
		});
	}
}

class Instance {
	string savePath;
	OneFileManager onefileMgr;

	this() {
		savePath = buildPath(buildPath(dirName(thisExePath), "local.envman"));
		onefileMgr = new OneFileManager(this);
	}

	this(string customSavePath) {
		savePath = customSavePath;
		onefileMgr = new OneFileManager(this);
	}

	TOMLDocument getConfig(bool mustExist = true) {
		if (exists(savePath)) {
			return parseTOML(readText(savePath), TOMLOptions.unquotedStrings);
		}
		if (mustExist) {
			throw new Exception("No configuration found.");
		}
		return parseTOML("");
	}

	void saveConfig(TOMLDocument doc)
	{
		auto buffer = appender!string();

		writeTomlTable(doc, buffer);

		std.file.write(savePath, buffer.data);
	}

	TOMLValue[string] getPathsTable() {
		auto doc = getConfig(false);
		if ("paths" !in doc) {
			TOMLValue[string] emptyTable;
			doc["paths"] = TOMLValue(emptyTable);
		}
		return doc["paths"].table;
	}

	void savePathsTable(TOMLValue[string] pathsTable) {
		auto doc = getConfig(false);
		doc["paths"] = TOMLValue(pathsTable);
		saveConfig(doc);
	}

	void updatePathsTable(void delegate(ref TOMLValue[string]) @safe updater) {
		auto tbl = getPathsTable();
		updater(tbl);
		savePathsTable(tbl);
	}

	TOMLValue[string] getPackagesTable() {
		auto doc = getConfig(false);
		if ("packages" !in doc) {
			TOMLValue[string] emptyTable;
			doc["packages"] = TOMLValue(emptyTable);
		}
		return doc["packages"].table;
	}

	void savePackagesTable(TOMLValue[string] packagesTable) {
		auto doc = getConfig(false);
		doc["packages"] = TOMLValue(packagesTable);
		saveConfig(doc);
	}

	void updatePackagesTable(void delegate(ref TOMLValue[string]) @safe updater) {
		auto tbl = getPackagesTable();
		updater(tbl);
		savePackagesTable(tbl);
	}

	TOMLValue[string] getConfigValuesTable() {
		auto doc = getConfig(false);
		if ("config" !in doc) {
			TOMLValue[string] emptyTable;
			doc["config"] = TOMLValue(emptyTable);
		}
		return doc["config"].table;
	}

	void saveConfigValuesTable(TOMLValue[string] configTable) {
		auto doc = getConfig(false);
		doc["config"] = TOMLValue(configTable);
		saveConfig(doc);
	}

	void updateConfigValuesTable(void delegate(ref TOMLValue[string]) @safe updater) {
		auto tbl = getConfigValuesTable();
		updater(tbl);
		saveConfigValuesTable(tbl);
	}

	string getConfigValue(string key, string defaultValue = "") {
		auto tbl = getConfigValuesTable();
		if (key in tbl && tbl[key].type == TOML_TYPE.STRING) {
			return tbl[key].str;
		}
		return defaultValue;
	}
}


class PathAddCommand : Command {
	this() {
		super("add");
		description = "Add a directory or file path with a slug";
		usage = "<slug> <path>";
		argCollType = ArgCollectionType.exact;
		argCount = 2; 
	}

	override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string slug = args[0];
		string pathArg = absolutePath(args[1]);

		try {
			instance.updatePathsTable((ref paths) {
				paths[slug] = TOMLValue(pathArg);
			});
		} catch (Exception e) {
			return CommandResult.error("Failed to save path: " ~ e.msg);
		}

		return CommandResult.ok("Added " ~ slug ~ " -> " ~ pathArg);
	}
}

class PathDeleteCommand : Command {
	this() {
		super("delete");
		description = "Delete a directory or file path for a slug";
		usage = "<slug>";
		argCollType = ArgCollectionType.exact;
		argCount = 1;
	}

	override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string slug = args[0];

		try {
			bool deleted = false;
			instance.updatePathsTable((ref paths) {
				if ((slug in paths) !is null) {
					paths.remove(slug);
					deleted = true;
				}
			});
			if (deleted) return CommandResult.ok("Deleted " ~ slug);
			return CommandResult.error("Slug " ~ slug ~ " not found.");
		} catch (Exception e) {
			return CommandResult.error("Failed to delete path: " ~ e.msg);
		}
	}
}

class PathGetCommand : Command {
	this() {
		super("get");
		description = "Gets the path of a slug entry";
		usage = "<slug>";
		argCollType = ArgCollectionType.minimum;
		argCount = 1;
		addOption("--open", "-o", "Open the path in default application");
		addOption("--path", "-p", "Adds the path to system path");
		addOption("--cd", "-c", "Change directory");
		addOption("--edit", "-e", "Open the path in a editor");
	}

	override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		auto paths = instance.getPathsTable();
		
		if (args.length == 0) {
			return CommandResult.error("No path slug provided.");
		}
		
		string slug = args[0];

		if ((slug in paths) is null) {
			return CommandResult.error("Slug " ~ slug ~ " not found.");
		}

		string path = paths[slug].str;

		if (hasOption("--edit", "-e")) {
			version(Windows) string defEditor = "notepad.exe";
			else string defEditor = "nano";

			string editor = instance.getConfigValue(ConfigKey.editor, environment.get("EDITOR", defEditor));
			if (!quiet) writefln("Opening %s in %s...", path, editor);

			auto pid = spawnShell(format("%s \"%s\"", editor, path));
			wait(pid);
			return CommandResult.ok();
		}

		if (hasOption("--open", "-o")) {
			executeShell("start \"\" \"" ~ path ~ "\"");
			return CommandResult.ok();
		}

		if (hasOption("--cd", "-c")) {
			chdir(path);
			return CommandResult.ok();
		}

		write(path);
		return CommandResult.ok();
	}	
}
class PathListCommand : Command {
	this() {
		super("list");
		description = "Lists all paths";
		usage = "";
		argCollType = ArgCollectionType.any;
		argCount = 0;
	}

	override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		try {
			auto paths = instance.getPathsTable();
			if (paths.length == 0) {
				writeln("No paths found.");
			} else {
				if (!quiet) writefln("Total Of %d entries\n", paths.length);
				foreach (key, val; paths) {
					writeln(key ~ " -> " ~ val.str);
				}
			}
			return CommandResult.ok();
		} catch (Exception e) {
			return CommandResult.error("Failed to list paths: " ~ e.msg);
		}
	}
}

class PathSearchCommand : Command {
	this() {
		super("search");
		description = "Search paths by slug or value";
		usage = "<query>";
		argCollType = ArgCollectionType.exact;
		argCount = 1;
	}

	override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string query = args[0].toLower();

		try {
			auto paths = instance.getPathsTable();
			if (paths.length == 0) {
				writeln("No paths found.");
				return CommandResult.ok();
			}

			import std.algorithm.sorting : sort;
			auto re = regex(query, "i");
			
			alias MatchResult = Tuple!(string, "key", string, "val", size_t, "dist");
			MatchResult[] matches;

			foreach (key, val; paths) {
				size_t dist = levenshtein(key.toLower(), query);
				size_t valDist = levenshtein(val.str.toLower(), query);
				
				if (key.toLower().canFind(query) || val.str.toLower().canFind(query)) {
					dist = 0;
				} else {
					dist = min(dist, valDist);
				}

				if (dist <= 5) {
					matches ~= MatchResult(key, val.str, dist);
				}
			}

			if (matches.length == 0) {
				writeln("No matching paths found.");
				return CommandResult.ok();
			}

			matches.sort!((a, b) => a.dist < b.dist);

			foreach(m; matches) {
				string keyOut = replaceAll(m.key, re, "<yellow>$&</yellow>");
				string valOut = replaceAll(m.val, re, "<yellow>$&</yellow>");
				cwriteln(keyOut ~ " = " ~ valOut);
			}

			return CommandResult.ok();
		} catch (Exception e) {
			return CommandResult.error("Failed to search paths: " ~ e.msg);
		}
	}
}

class PathEditCommand : Command {
	this() {
		super("edit");
		description = "Edit an existing path for a slug";
		usage = "<slug> <path>";
		argCollType = ArgCollectionType.exact;
		argCount = 2;
	}

	override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string slug = args[0];
		string pathArg = absolutePath(args[1]);

		try {
			bool found = false;
			instance.updatePathsTable((ref paths) {
				if ((slug in paths) !is null) {
					paths[slug] = TOMLValue(pathArg);
					found = true;
				}
			});
			if (!found) {
				return CommandResult.error("Slug " ~ slug ~ " not found.");
			}
			return CommandResult.ok("Edited " ~ slug ~ " -> " ~ pathArg);
		} catch (Exception e) {
			return CommandResult.error("Failed to edit path: " ~ e.msg);
		}
	}
}

class PathSetCommand : Command {
	this() {
		super("set");
		description = "Sets the path for the current shell or permanently";
		usage = "<slug> [-p|--path] [-g|--global]";
		argCollType = ArgCollectionType.minimum;
		argCount = 1;
		addOption("--path", "-p", "Adds to current shell PATH (prints set command)");
		addOption("--global", "-g", "Adds with setx permanently (Windows only)");
	}

	override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		auto paths = instance.getPathsTable();
		string slug;
		
		foreach (arg; args) {
			if (arg[0] != '-') {
				slug = arg;
				break;
			}
		}

		if (slug.length == 0) {
			return CommandResult.error("No path slug provided.");
		}

		if ((slug in paths) is null) {
			return CommandResult.error("Slug " ~ slug ~ " not found.");
		}

		string path = paths[slug].str;

		if (hasOption("--global", "-g")) {
			version (Windows) {
				import std.process : execute;
				import std.format : format;
				auto res = execute(["setx", "PATH", format("%%PATH%%;%s", path)]);
				if (res.status == 0) {
					return CommandResult.ok("Path added permanently via setx.");
				} else {
					return CommandResult.error("Failed to execute setx: " ~ res.output);
				}
			} else {
				return CommandResult.error("--global is only supported on Windows.");
			}
		}

		if (hasOption("--path", "-p")) {
			writefln("set PATH=%s;%%PATH%%", path);
			return CommandResult.ok();
		}

		return CommandResult.error("Please specify --path (-p) or --global (-g)");
	}
}

class PathCommand : Command {
	this() {
		super("path");
		description = "Show the save path of envman or manage paths";
		usage = "";
		argCollType = ArgCollectionType.any;
		registerSubCommand(new PathAddCommand());
		registerSubCommand(new PathSetCommand());
		registerSubCommand(new PathDeleteCommand());
		registerSubCommand(new PathEditCommand());
		registerSubCommand(new PathListCommand());
		registerSubCommand(new PathSearchCommand());
		registerSubCommand(new PathGetCommand());
	}

	override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		if (args.length == 0) {
			writeln(instance.savePath);
			return CommandResult.ok();
		}
		return CommandResult.error("Unknown command: " ~ args[0], 1);
	}
}


class PkgRunCommand : Command {
	this() {
		super("run");
		description = "Runs an action (like 'run' or 'build') defined in a package's metadata";
		argCollType = ArgCollectionType.minimum;
		usage = "<package alias> [action] [args...]";
		argCount = 1;
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string aliasName = args[0];
		string action = args.length > 1 ? args[1] : "run";
		string[] extraArgs = args.length > 2 ? args[2..$] : [];

		bool success;
		string errorMsg;
		ProjectFileManager pMgr = new ProjectFileManager(".");
		auto configs = pMgr.getPackagesConfig(true, success, errorMsg);
		
		string targetDir = ".";
		if (success) {
			foreach(cfg; configs) {
				if (cfg.aliasName == aliasName) {
					targetDir = cfg.dest;
					break;
				}
			}
		}

		try {
			Package pkg = instance.onefileMgr.getPackageOrFail(aliasName);
			
			string cwd = exists(targetDir) && isDir(targetDir) ? targetDir : ".";
			runPackageAction(pkg, cwd, action, extraArgs);
			return CommandResult.ok();
		} catch (Exception e) {
			return CommandResult.error("Failed to run action: " ~ e.msg);
		}
	}
}

class PkgImportCommand : Command {
	this() {
		super("import");
		description = "Imports and registers multiple packages from a registry list file";
		argCollType = ArgCollectionType.exact;
		usage = "<registry_list_file>.toml";
		argCount = 1;
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string listFile = args[0];
		if (!exists(listFile)) return CommandResult.error("File not found: " ~ listFile);
		
		Package singlePkg;
		try {
			if (instance.onefileMgr.registerFromFile(listFile, singlePkg)) {
				return CommandResult.ok("Imported single package: " ~ singlePkg.name);
			}
		} catch (Exception e) {
			return CommandResult.error(e.msg);
		}

		try {
			auto doc = parseTOML(readText(listFile));
			if ("packages" !in doc || doc["packages"].type != TOML_TYPE.ARRAY) {
				return CommandResult.error("Invalid registry list: 'packages' array missing. If you are importing a single file, ensure it has the .envman.package extension.");
			}
			
			int count = 0;
			string listDir = absolutePath(dirName(listFile));

			foreach(v; doc["packages"].array) {
				if (v.type == TOML_TYPE.STRING) {
					string path = v.str;
					if (path.endsWith(".envman.package")) {
						if (!isRemoteUrl(path) && !isRooted(path)) {
							path = buildNormalizedPath(listDir, path);
						}
						
						Package p;
						if (instance.onefileMgr.registerFromFile(path, p)) {
							if (!quiet) writefln("Imported: %s", p.name);
							count++;
						} else {
							if (!quiet) writefln("Failed to register: %s", path);
						}
					}
				}
			}
			return CommandResult.ok(format("Successfully imported %d package(s).", count));
		} catch (Exception e) {
			return CommandResult.error("Failed to import registry list: " ~ e.msg);
		}
	}
}

class PkgRegisterCommand : Command {
	this() {
		super("register");
		description = "Registers a file/directory/url or .envman.package as a package on global package registery";
		argCollType = ArgCollectionType.minimum;
		usage = "<package alias> <package path> OR <package_file>.envman.package";
		argCount = 1;
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		Package pkg;
		try {
			if (instance.onefileMgr.registerFromFile(args[0], pkg)) {
				return CommandResult.ok("Registered package from file: " ~ pkg.name);
			}
		} catch (Exception e) {
			return CommandResult.error(e.msg);
		}

		if (args.length < 2) return CommandResult.error("Usage: " ~ usage);

		string aliasName = args[0];
		string packagePath = args[1];

		string finalPath = packagePath;
		if (!isRemoteUrl(finalPath)) {
			finalPath = absolutePath(packagePath);
		}

		try {
			if (!instance.onefileMgr.registerPackage(aliasName, finalPath)) {
				return CommandResult.error("Registration returned failure.");
			}
		} catch (Exception e) {
			return CommandResult.error("Failed to register package: " ~ e.msg);
		}

		return CommandResult.ok("Registered package " ~ aliasName ~ " -> " ~ finalPath);
	}
}


class PkgInstallCommand : Command {
	this() {
		super("install");
		description = "Installs packages from " ~ (new ProjectFileManager()).fileName ~ " into the current directory";
		argCollType = ArgCollectionType.minimum;
		usage = "[target directory path]";
		argCount = 0;

		addOption("--symlink", "-s", "Use symlinks for local packages instead of copying");
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		Package pkg;
		bool useSymlink = hasOption("--symlink", "-s");
		try {
			if (args.length > 0 && instance.onefileMgr.registerFromFile(args[0], pkg)) {
				auto mgr = new ProjectFileManager();
				if (!mgr.hasEntry(pkg.name)) {
					mgr.addEntry(pkg.name, pkg.name);
				}
				
				return processPackages([ "."], quiet, false, useSymlink);
			}
		} catch (Exception e) {
			return CommandResult.error(e.msg);
		}
		return processPackages(args, quiet, false, useSymlink);
	}
}

class PkgUpgradeCommand : Command {
	this() {
		super("upgrade");
		description = "Upgrades packages from " ~ (new ProjectFileManager()).fileName ~ " by checking if the source is modified";
		argCollType = ArgCollectionType.minimum;
		usage = "[target directory path]";
		argCount = 0;

		addOption("--symlink", "-s", "Use symlinks for local packages instead of copying");
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		return processPackages(args, quiet, true, hasOption("--symlink", "-s"));
	}
}

class PkgCheckCommand : Command {
	this() {
		super("check");
		description = "Checks packages in "~ (new ProjectFileManager()).fileName ~ " without installing";
		argCollType = ArgCollectionType.minimum;
		usage = "[target directory path]";
		argCount = 0;

		addOption("--fix", "-fix", "Removes unregistered (unknown) packages from packages.envman file");		
		addOption("--details", "-d", "Gives more details about the project");
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string targetDir = args.length > 0 ? args[0] : ".";
		bool giveDetails = hasOption("--details", "-d");

		bool success;
		string errorMsg;
		ProjectFileManager pMgr = new ProjectFileManager(targetDir);
		Project project = pMgr.getProject();
		PackageConfig[] configs = pMgr.getPackagesConfig(quiet, success, errorMsg);
		
		if (!success) {
			if (!quiet) cwritefln("<yellow>Notice:</yellow> Not using envman onefile in current directory, or failed to parse. (<red>%s</red>)", errorMsg);
			return CommandResult.ok();
		}


		if (!quiet) {
			if (giveDetails) {
				cwritefln("Project %s (v%s) [envman version used: %s]", project.name, project.version_, project.envmanVersion);
			}
			writefln("Status: envman onefile in use (%d packages defined).", configs.length);
		}

		string[] unregistered;

		foreach (cfg; configs) {
			writefln("- Package: %s", cfg.aliasName);
			if (!instance.onefileMgr.isPackageExists(cfg.aliasName)) {
				cwritefln("  Status: [<red>Unregistered</red>] (Missing from global registry, use --fix to remove it from " ~ pMgr.fileName ~ ")");
				if (cfg.description.length > 0) cwritefln("    - Description: <lcyan>%s</lcyan>", cfg.description);
				if (cfg.obtainFrom.length > 0) cwritefln("    - Obtain from: <lcyan>%s</lcyan>", cfg.obtainFrom);
				unregistered ~= cfg.aliasName;
				continue;
			}

			auto pkgResult = instance.onefileMgr.getPackage(cfg.aliasName);
			Package pkg = pkgResult[1];
			string absoluteDest = buildPath(targetDir, cfg.dest);

			if (pkg.pathKind == "url") {
				writefln("  Status: URL Package (Cannot accurately check time, run upgrade to force fetch)");
			} else {
				if (!exists(pkg.path)) {
					cwritefln("  Status: [<red>Local Source Missing</red>] (%s)", pkg.path);
				} else if (!exists(absoluteDest)) {
					cwritefln("  Status: [<red>Missing Locally</red>] (needs install)");
				} else if (isSourceNewer(pkg.path, absoluteDest)) {
					cwritefln("  Status: [<on_cyan>Needs Upgrade</on_cyan>] (Source is newer)");
				} else {
					cwritefln("  Status: [<green>Up to date</green>]");
				}
			}
		}

		if (hasOption("--fix", "-fix")) {
			if (unregistered.length > 0) {
				try {
					auto mgr = new ProjectFileManager(targetDir);
					mgr.removeEntries(unregistered);
					cwritefln("\nFixed: Removed <yellow>%d</yellow> unregistered package(s) from " ~ mgr.fileName ~ ".", unregistered.length);
				} catch (Exception e) {
					return CommandResult.error("Failed to fix " ~ (new ProjectFileManager(targetDir)).fileName ~ ": " ~ e.msg);
				}
			} else {
				if (!quiet) cwritefln("\n<green>Everything is perfectly aligned!</green>");
			}
		}

		return CommandResult.ok();
	}
}

class PkgListCommand : Command {
	this() {
		super("list");
		description = "List all packages in global registery";
		argCollType = argCollType.any;
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		Package[] packages = instance.onefileMgr.getAllPackages();
		if (packages.length == 0) {
			if (!quiet) writeln("No packages found in global registry.");
			return CommandResult.ok();
		}

		if (!quiet) writefln("Found %d package(s) in global registry:", packages.length);
		foreach (pkg; packages) {
			writefln("- %s -> %s (%s)", pkg.name, pkg.path, pkg.pathKind);
		}
		return CommandResult.ok();
	}
}

class PkgInfoCommand : Command {
	this() {
		super("info");
		description = "Information about a registery package";
		usage = "<package name>";
		argCollType = argCollType.minimum;
		argCount = 1;
		
		addOption("--path", "-p", "Get path of the package");
		addOption("--dir", "-d", "Give the directory path of the package (for local packages)");
		addOption("--edit", "-e", "Open the path in users text editor");
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string packageName = args[0];
		try {
			Package pkg = instance.onefileMgr.getPackageOrFail(packageName);

			bool showPath = hasOption("--path", "-p");
			bool showDir = hasOption("--dir", "-d");
			bool edit = hasOption("--edit", "-e");
			
			if (edit) {
				version(Windows) string defEditor = "notepad.exe";
				else string defEditor = "nano";

				string editor = instance.getConfigValue(ConfigKey.editor, environment.get("EDITOR", defEditor));
				if (!quiet) writefln("Opening %s in %s...", pkg.name, editor);

				auto pid = spawnShell(format("%s \"%s\"", editor, pkg.path));
				wait(pid);
				return CommandResult.ok();
			}

			if (showPath || showDir) {
				string path = pkg.path;
				if (!isRemoteUrl(path) && showDir) path = dirName(pkg.path);
				write(path);
				return CommandResult.ok();
			}

			cwritefln("Package <green>%s</green>
\tLocation (Path): %s
\tLocation (Path) Type: %s
\tTags: %s", pkg.name, pkg.path, pkg.pathKind, pkg.tags);
			return CommandResult.ok();
		} catch (Exception e) {
			return CommandResult.error(e.msg);
		}
	}
}

class PkgRemoveCommand : Command {
	this() {
		super("remove");
		description = "Removes a package from the global registry";
		argCollType = ArgCollectionType.minimum;
		usage = "<package alias>";
		argCount = 1;
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string aliasName = args[0];

		try {
			instance.onefileMgr.getPackageOrFail(aliasName);
			if (instance.onefileMgr.removePackage(aliasName)) {
				return CommandResult.ok("Package '" ~ aliasName ~ "' successfully removed.");
			} else {
				return CommandResult.error("Failed to remove package '" ~ aliasName ~ "'.");
			}
		} catch (Exception e) {
			return CommandResult.error("Failed to remove package: " ~ e.msg);
		}
	}
}

class PkgAddCommand : Command {
	this() {
		super("add");
		description = "Adds a package requirement to " ~ PROJECT_FILE ~ " in the current directory";
		argCollType = ArgCollectionType.minimum;
		usage = "<package alias> <destination path>";
		argCount = 2;
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string aliasName = args[0];
		string destination = args[1];

		Package pkg;
		try {
			if (instance.onefileMgr.registerFromFile(args[0], pkg)) {
				aliasName = pkg.name;
			}
			instance.onefileMgr.getPackageOrFail(aliasName);
		} catch (Exception e) {
			return CommandResult.error(e.msg);
		}

		auto mgr = new ProjectFileManager();
		try {
			mgr.addEntry(aliasName, destination);
		} catch (Exception e) {
			return CommandResult.error("Failed to update " ~ mgr.fileName ~ ": " ~ e.msg);
		}

		cwritefln("Added <green>'%s'</green> -&gt; <green>'%s'</green> to " ~ mgr.fileName, aliasName, destination);
		return CommandResult.ok();
	}
}


class PkgDropCommand : Command {
	this() {
		super("drop");
		description = "Removes a package entry from " ~ PROJECT_FILE ~ " in the current directory";
		argCollType = ArgCollectionType.minimum;
		usage = "<package alias>";
		argCount = 1;
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string aliasName = args[0];
		auto mgr = new ProjectFileManager();

		if (!mgr.exists()) {
			return CommandResult.error("No " ~ mgr.fileName ~ " found in current directory.");
		}

		if (!mgr.hasEntry(aliasName)) {
			return CommandResult.error("Package '" ~ aliasName ~ "' is not listed in " ~ mgr.fileName ~ ".");
		}

		try {
			mgr.removeEntry(aliasName);
		} catch (Exception e) {
			return CommandResult.error("Failed to update " ~ mgr.fileName ~ ": " ~ e.msg);
		}

		if (!quiet) cwritefln("Dropped <yellow>'%s'</yellow> from " ~ mgr.fileName ~ ".", aliasName);
		return CommandResult.ok();
	}
}

class PkgInspect : Command {
	this() {
		super("inspect");
		description = "Shows detailed information about a local project package dependency";
		argCollType = ArgCollectionType.minimum;
		argCount = 1;
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		ProjectFileManager pMgr = new ProjectFileManager();
		return CommandResult.error("Not implemented yet.");
	}
}
class PkgCommand : Command {
	this() {
		super("pkg");
		description = "Onefile package system";

		registerSubCommand(new PkgRegisterCommand());
		registerSubCommand(new PkgAddCommand());
		registerSubCommand(new PkgDropCommand());
		registerSubCommand(new PkgInstallCommand());
		registerSubCommand(new PkgInfoCommand());
		registerSubCommand(new PkgListCommand());
		registerSubCommand(new PkgUpgradeCommand());
		registerSubCommand(new PkgCheckCommand());
		registerSubCommand(new PkgRemoveCommand());
		registerSubCommand(new PkgRunCommand());
		registerSubCommand(new PkgImportCommand());
		registerSubCommand(new PkgInspect());
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		if (args.length == 0)
			return CommandResult.ok(buildHelp());

		return CommandResult.error(format("Unknown command: %s\n\n%s", args[0], buildHelp()) , 1);
	}
}

class ConfigSetCommand : Command {
	this() {
		super("set");
		description = "Set a configuration value";
		usage = "<key> <value>";
		argCollType = ArgCollectionType.exact;
		argCount = 2;
	}

	override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string key = args[0];
		string value = args[1];

		try {
			instance.updateConfigValuesTable((ref cfg) {
				cfg[key] = TOMLValue(value);
			});
			return CommandResult.ok(format("Config set: %s -> %s", key, value));
		} catch (Exception e) {
			return CommandResult.error("Failed to set config: " ~ e.msg);
		}
	}
}

class ConfigGetCommand : Command {
	this() {
		super("get");
		description = "Get a configuration value";
		usage = "<key>";
		argCollType = ArgCollectionType.exact;
		argCount = 1;

		addOption("--execute", "-e", "Execute value of the config key as a shell command");
	}

	override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string key = args[0];
		auto tbl = instance.getConfigValuesTable();

		if (key in tbl) {
			string val = tbl[key].str;
			
			if (hasOption("--execute", "-e")) {
				string shell = instance.getConfigValue(ConfigKey.shell);
				Pid pid;
				if (shell.length > 0) {
					if (shell.toLower().canFind("cmd")) {
						pid = spawnShell(val, null, Config.none, getcwd());
					} else {
						pid = spawnProcess([shell, "-c", val], null, Config.none, getcwd());
					}
				} else {
					pid = spawnShell(val, null, Config.none, getcwd());
				}
				wait(pid);
			} else {
				if (quiet) write(val);
				else writeln(val);
			}
			
			return CommandResult.ok();
		}
		return CommandResult.error("Config key '" ~ key ~ "' not found.");
	}
}

class ConfigDeleteCommand : Command {
	this() {
		super("delete");
		description = "Delete a configuration value";
		usage = "<key>";
		argCollType = ArgCollectionType.exact;
		argCount = 1;
	}

	override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string key = args[0];
		bool removed = false;
		try {
			instance.updateConfigValuesTable((ref cfg) {
				if (key in cfg) {
					cfg.remove(key);
					removed = true;
				}
			});
			if (removed) return CommandResult.ok("Config key '" ~ key ~ "' removed.");
			return CommandResult.error("Config key '" ~ key ~ "' not found.");
		} catch (Exception e) {
			return CommandResult.error("Failed to delete config: " ~ e.msg);
		}
	}
}

class ConfigListCommand : Command {
	this() {
		super("list");
		description = "List all configuration values";
		argCollType = ArgCollectionType.any;
	}

	override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		auto tbl = instance.getConfigValuesTable();
		if (tbl.length == 0) {
			if (!quiet) writeln("No configuration values set.");
			return CommandResult.ok();
		}

		foreach (key, val; tbl) {
			writefln("%s -> %s", key, val.str);
		}
		return CommandResult.ok();
	}
}

class ConfigCommand : Command {
	this() {
		super("config");
		description = "Manage user configuration";
		registerSubCommand(new ConfigSetCommand());
		registerSubCommand(new ConfigGetCommand());
		registerSubCommand(new ConfigListCommand());
		registerSubCommand(new ConfigDeleteCommand());
	}

	override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		if (args.length == 0)
			return CommandResult.ok(buildHelp());
		return CommandResult.error("Unknown command: " ~ args[0], 1);
	}
}

class ProjectInfoCommand : Command {
	this() {
		super("info");
		description = "Display information about the current project";
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		auto mgr = new ProjectFileManager(getcwd());
		if (!mgr.exists()) {
			return CommandResult.error("No " ~ mgr.fileName ~ " found in current directory.");
		}
		
		Project pj = mgr.getProject();
		cwritefln("Project: <cyan>%s</cyan> (v%s)", pj.name, pj.version_);
		if (pj.description != "Unknown") cwritefln("\tDescription: %s", pj.description);
		if (pj.authors.length > 0) cwritefln("\tAuthors: %s", pj.authors.join(","));
		if (pj.license != "Unknown") cwritefln("\tLicense: %s", pj.license);
		if (pj.homepage != "Unknown") cwritefln("\tHomepage: %s", pj.homepage);
		if (pj.repository != "Unknown") cwritefln("\tRepository: %s", pj.repository);
		if (pj.keywords.length > 0) cwritefln("\tKeywords: %s", pj.keywords);
		cwritefln("\tEnvman Version: %s", pj.envmanVersion);
		
		return CommandResult.ok();
	}
}

class ProjectInitCommand : Command {
	this() {
		super("init");
		description = "Initialize a new project in the current directory";
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string targetDir = getcwd();
		try {
			ProjectFileManager pMgr = new ProjectFileManager(targetDir);
			Project pj;
			pj.name = baseName(absolutePath(targetDir));
			pj.version_ = "0.1.0";
			if (!pMgr.init(pj)) {
				return CommandResult.error("A " ~ pMgr.fileName ~ " file already exists in this directory.");
			}
			return CommandResult.ok("Successfully initialized project in " ~ targetDir);
		} catch (Exception e) {
			return CommandResult.error("Failed to initialize: " ~ e.msg);
		}
	}
}

class ProjectCommand : Command {
	this() {
		super("project");
		description = "Manage project configuration (" ~ PROJECT_FILE ~ ")";
		registerSubCommand(new ProjectInfoCommand());
		registerSubCommand(new ProjectInitCommand());
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		if (args.length == 0)
			return CommandResult.ok(buildHelp());

		return CommandResult.error(format("Unknown command: %s\n\n%s", args[0], buildHelp()) , 1);
	}
}

class InfoCommand : Command {
	this() {
		super("info");
		description = "Information about the envman";
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		cwritefln("envman (version: <green>%s</green>)

Envman is a dev environment / package manager.

Created By Kerem ATA (zoda)
Licensed under the MIT License

This copy of envman is compiled at %s

© 2026", ENVMAN_VERSION, COMPILED_AT);
		return CommandResult.ok();
	}
}

class RootCommand : Command {
	this() { 
		super("envman"); 
		description = format("Envman %s, environment/package manager", ENVMAN_VERSION);
		
		addOption("--verbose", "-V", "Enable verbose output");
		addOption("--quiet", "-q", "Suppress output");
		addOption("--gen-docs", "-gd", "Generate markdown documentation for all commands");
		addOption("--gen-html", "-gh", "Generate HTML documentation for all commands");
		addOption("--version", "-v", "Version of the envman");

		registerSubCommand(new PathSetCommand());
		registerSubCommand(new PathCommand());
		registerSubCommand(new PkgCommand());
		registerSubCommand(new ProjectCommand());
		registerSubCommand(new ConfigCommand());
		registerSubCommand(new InfoCommand());
	}

	override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		if (hasOption("--gen-docs", "-gd")) {
			std.file.write("DOCUMENTATION.md", buildMarkdown());
			cwritefln("<green>Documentation generation complete!</green> Saved to DOCUMENTATION.md");
			return CommandResult.ok();
		}

		if (hasOption("--gen-html", "-gh")) {
			std.file.write("DOCUMENTATION.html", this.buildHTML());
			cwritefln("<green>HTML Documentation generation complete!</green> Saved to DOCUMENTATION.html");
			return CommandResult.ok();
		}

		if (hasOption("--version", "-v")) {
			if (hasOption("--quiet","-q")) writeln(ENVMAN_VERSION);
			cwritefln("envman, version <green>%s</green>",ENVMAN_VERSION);
			return CommandResult.ok();
		}

		if (args.length == 0)
			return CommandResult.ok(buildHelp());

		return CommandResult.error("Unknown command: " ~ args[0], 1);
	}
}


// --functions
// functions

int levenshtein(string a, string b)
{
    size_t n = a.length;
    size_t m = b.length;

    int[][] dp = new int[][](n + 1, m + 1);

    foreach (size_t i; 0 .. n + 1)
        dp[i][0] = cast(int)i;

    foreach (size_t j; 0 .. m + 1)
        dp[0][j] = cast(int)j;

    foreach (size_t i; 1 .. n + 1)
    foreach (size_t j; 1 .. m + 1)
    {
        int cost = (a[i - 1] == b[j - 1]) ? 0 : 1;

        dp[i][j] = min(
            dp[i - 1][j] + 1,
            dp[i][j - 1] + 1,
            dp[i - 1][j - 1] + cost
        );
    }

    return dp[n][m];
}

Package packageFromTOML(string name, TOMLValue val) {
	Package p;
	p.name = name;
	if (val.type == TOML_TYPE.STRING) {
		p.path = val.str;
	} else if (val.type == TOML_TYPE.TABLE) {
		auto tbl = val.table;
		if ("path" in tbl) p.path = tbl["path"].str;
		p.tags = extractStringArray(tbl, "tags");
		foreach (k, v; tbl) {
			if (k != "path" && k != "tags") p.metadata[k] = v;
		}
	}
	p.pathKind = isRemoteUrl(p.path) ? "url" : "local";
	return p;
}

string[] extractStringArray(TOMLValue[string] tbl, string key) {
	string[] result;
	if (key in tbl && tbl[key].type == TOML_TYPE.ARRAY) {
		foreach(v; tbl[key].array) {
			if (v.type == TOML_TYPE.STRING) result ~= v.str;
		}
	}
	return result;
}

string buildPathFromTOMLArray(TOMLValue arrayNode) {
	string[] parts;
	foreach(v; arrayNode.array) {
		if (v.type == TOML_TYPE.STRING) parts ~= v.str;
	}
	return buildPath(parts);
}

bool isRemoteUrl(string path) {
	return path.startsWith("http://") || path.startsWith("https://");
}

CommandResult processPackages(string[] args, bool quiet, bool isUpgrade, bool useSymlink = false) {
	string targetDir = args.length > 0 ? args[0] : ".";
	
	bool success;
	string errorMsg;
	ProjectFileManager pMgr = new ProjectFileManager(targetDir);
	PackageConfig[] configs = pMgr.getPackagesConfig(quiet, success, errorMsg);
	
	if (!success) {
		return CommandResult.error(errorMsg);
	}

	foreach(cfg; configs) {
		if (!instance.onefileMgr.isPackageExists(cfg.aliasName)) {
			if (!quiet) writeln("Package not found in global registry: ", cfg.aliasName);
			continue;
		}

		auto pkgResult = instance.onefileMgr.getPackage(cfg.aliasName);
		Package pkg = pkgResult[1];
		
		if (pkg.pathKind == "url") {
			installUrlPackage(cfg, targetDir, pkg, quiet, isUpgrade);
		} else {
			installLocalPackage(cfg, targetDir, pkg, quiet, isUpgrade, useSymlink);
		}
	}

	return CommandResult.ok(isUpgrade ? "Packages upgraded successfully" : "Packages installed successfully");
}

Package parsePackageFile(string filePath) {
	if (!exists(filePath)) throw new Exception("Package file not found: " ~ filePath);
	auto doc = parseTOML(readText(filePath));
	string name = baseName(filePath, ".envman.package");
	if ("name" in doc && doc["name"].type == TOML_TYPE.STRING) {
		name = doc["name"].str;
	}
	auto p = packageFromTOML(name, TOMLValue(doc.table));
	if (!isRemoteUrl(p.path) && !isRooted(p.path)) {
		p.path = buildNormalizedPath(absolutePath(dirName(filePath)), p.path);
	}
	return p;
}

void runPackageAction(Package pkg, string targetDir, string action, string[] extraArgs) {
	string actionCmd;

	if ("commands" in pkg.metadata && pkg.metadata["commands"].type == TOML_TYPE.TABLE) {
		auto cmds = pkg.metadata["commands"].table;
		if (action in cmds && cmds[action].type == TOML_TYPE.STRING) {
			actionCmd = cmds[action].str;
		}
	}

	if (actionCmd.length == 0) {
		if (action in pkg.metadata && pkg.metadata[action].type == TOML_TYPE.STRING) {
			actionCmd = pkg.metadata[action].str;
		} else if (action == "run" && "executable" in pkg.metadata && pkg.metadata["executable"].type == TOML_TYPE.STRING) {
			actionCmd = pkg.metadata["executable"].str;
		}
	}

	if (actionCmd.length == 0) {
		string msg = "Action '" ~ action ~ "' not found in package '" ~ pkg.name ~ "' metadata.";
		if ("commands" !in pkg.metadata) {
			msg ~= " No [commands] section defined.";
		} else {
			msg ~= " Check your [commands] section.";
		}
		throw new Exception(msg);
	}

	string command = actionCmd;
	foreach (arg; extraArgs) {
		if (arg.canFind(" ")) {
			command ~= " \"" ~ arg ~ "\"";
		} else {
			command ~= " " ~ arg;
		}
	}


	auto pid = spawnShell(command, null, Config.none, targetDir);
	exit(wait(pid));
}

void copyRecursively(string source, string dest) {
	if (isDir(source)) {
		if (!exists(dest)) mkdirRecurse(dest);
		foreach (string name; dirEntries(source, SpanMode.shallow)) {
			copyRecursively(name, buildPath(dest, baseName(name)));
		}
	} else {
		if (!exists(dirName(dest))) mkdirRecurse(dirName(dest));
		std.file.copy(source, dest);
	}
}

bool isSourceNewer(string source, string dest) {
	if (!exists(dest)) return true;
	if (!exists(source)) return false;

	if (isDir(source)) {
		if (!isDir(dest)) return true;

		SysTime destNewest;
		bool destHasFiles = false;
		foreach (string name; dirEntries(dest, SpanMode.depth)) {
			if (!destHasFiles) destHasFiles = true;
			auto ts = timeLastModified(name);
			if (ts > destNewest) destNewest = ts;
		}
		if (!destHasFiles) return true;

		foreach (string name; dirEntries(source, SpanMode.depth)) {
			if (timeLastModified(name) > destNewest) return true;
		}
		return false;
	} else {
		if (isDir(dest)) return true;
		return timeLastModified(source) > timeLastModified(dest);
	}
}

void createSymlink(string target, string link) {
	version(Windows) {
		DWORD flags = isDir(target) ? 1 : 0;
		// SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE = 0x2
		flags |= 0x02; 
		
		if (CreateSymbolicLinkW(link.toUTF16z, target.toUTF16z, flags) == 0) {
			auto err = GetLastError();
			throw new Exception(format("Failed to create symlink (Error %d). Note: Symlinks on Windows require Developer Mode or Administrator privileges.", err));
		}
	} else {
		std.file.symlink(target, link);
	}
}

void installLocalPackage(PackageConfig cfg, string targetDir, Package pkg, bool quiet, bool isUpgrade, bool useSymlink = false) {
	string absoluteDest = buildPath(targetDir, cfg.dest);
	string sourceUrlOrPath = pkg.path;

	if (!exists(sourceUrlOrPath)) {
		if (!quiet) writeln("Local source not found for package ", cfg.aliasName, ": ", sourceUrlOrPath);
		return;
	}

	if (cfg.expectedType == "file" && isDir(sourceUrlOrPath)) {
		writeln("Error: Package ", cfg.aliasName, " is a directory, but expected a file.");
		return;
	}
	if (cfg.expectedType == "dir" && isFile(sourceUrlOrPath)) {
		writeln("Error: Package ", cfg.aliasName, " is a file, but expected a directory.");
		return;
	}

	if (isUpgrade && !useSymlink) {
		if (!isSourceNewer(sourceUrlOrPath, absoluteDest)) {
			if (!quiet) cwritefln("Package <cyan>%s</cyan> is up to date.", cfg.aliasName);
			return;
		}
		if (!quiet) writeln("Upgrading ", cfg.aliasName, " from ", sourceUrlOrPath, " -> ", absoluteDest);
	} else if (!useSymlink) {
		if (!quiet) writeln("Copying ", cfg.aliasName, " from ", sourceUrlOrPath, " -> ", absoluteDest);
	}

	try {
		if (useSymlink) {
			if (exists(absoluteDest)) {
				if (isSymlink(absoluteDest)) {
					remove(absoluteDest);
				} else {
					if (!quiet) writeln("Warning: Destination exists and is not a symlink. Skipping symlink for ", cfg.aliasName);
					return;
				}
			}
			if (!quiet) writeln("Symlinking ", cfg.aliasName, " from ", sourceUrlOrPath, " -> ", absoluteDest);
			createSymlink(sourceUrlOrPath, absoluteDest);
		} else {
			copyRecursively(sourceUrlOrPath, absoluteDest);
		}
	} catch (Exception e) {
		if (!quiet) writeln("Failed to install package ", cfg.aliasName, ": ", e.msg);
	}
}

string hashFile(string path) {
	import std.digest.sha : SHA256;
	import std.digest : toHexString;

	SHA256 sha;
	sha.start();
	auto f = File(path, "rb");
	foreach (chunk; f.byChunk(64 * 1024)) {
		sha.put(chunk);
	}
	return sha.finish().toHexString().idup;
}

void installUrlPackage(PackageConfig cfg, string targetDir, Package pkg, bool quiet, bool isUpgrade) {
	import requests;

	string absoluteDest = buildPath(targetDir, cfg.dest);
	string sourceUrlOrPath = pkg.path;
	
	if (cfg.expectedType == "dir") {
		writeln("Failed to download package ", cfg.aliasName, ": URL cannot be guaranteed to be a directory.");
		return;
	}

	try {
		if (!exists(dirName(absoluteDest))) mkdirRecurse(dirName(absoluteDest));

		auto rq = Request();
		rq.sslSetVerifyPeer(false);

		if (isUpgrade && exists(absoluteDest) && getSize(absoluteDest) > 0) {
			string tmpDest = absoluteDest ~ ".envman_tmp";
			scope(exit) { if (exists(tmpDest)) remove(tmpDest); }

			if (!quiet) writeln("Checking ", cfg.aliasName, " for updates...");
			auto rs = rq.get(sourceUrlOrPath);
			if (rs.code != 200) {
				if (!quiet) cwritefln("<red>Failed to download package</red> %s: HTTP Status %d", cfg.aliasName, rs.code);
				return;
			}
			auto tmpFile = File(tmpDest, "wb");
			tmpFile.rawWrite(rs.responseBody.data);
			tmpFile.close();

			if (getSize(tmpDest) == 0) {
				if (!quiet) cwritefln("<red>Download returned empty file for</red> %s, skipping.", cfg.aliasName);
				return;
			}

			string oldHash = hashFile(absoluteDest);
			string newHash = hashFile(tmpDest);

			if (oldHash == newHash) {
				if (!quiet) cwritefln("Package <cyan>%s</cyan> is up to date. (hash match)", cfg.aliasName);
				return;
			}

			std.file.copy(tmpDest, absoluteDest);
			if (!quiet) cwritefln("Upgraded <green>%s</green> (hash changed)", cfg.aliasName);
		} else {
			if (!quiet) writeln("Downloading ", cfg.aliasName, " from ", sourceUrlOrPath, " -> ", absoluteDest);
			auto rs = rq.get(sourceUrlOrPath);
			if (rs.code != 200) {
				if (!quiet) cwritefln("<red>Failed to download package</red> %s: HTTP Status %d", cfg.aliasName, rs.code);
				return;
			}
			auto file = File(absoluteDest, "wb");
			file.rawWrite(rs.responseBody.data);
		}
	} catch (Exception e) {
		if (!quiet) writeln("Failed to download package ", cfg.aliasName, ": ", e.msg);
	}
}

void writeTomlTable(TOMLValue[string] table, ref Appender!string outBuf, string indent = "")
{
	foreach (k, v; table)
	{
		if (v.type != TOML_TYPE.TABLE)
		{
			outBuf.put(format("%s = %s\n", k, v.toString()));
		}
	}

	foreach (k, v; table)
	{
		if (v.type == TOML_TYPE.TABLE)
		{
			outBuf.put(format("\n[%s%s]\n", indent, k));
			writeTomlTable(v.table, outBuf, (indent.length > 0 ? indent : "") ~ k ~ ".");
		}
	}
}

// all the magic happens right here

void main(string[] args) {
	instance = new Instance();
	
	auto root = new RootCommand();
	auto result = root.handle(args.length > 1 ? args[1 .. $] : []);
	
	if (result.message.length > 0) {
		writeln(result.message);
	}

	if (!result.success) {
		exit(result.exitCode);
	}
}

/* end of the beginning */