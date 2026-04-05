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
import std.file;
import std.process;
import std.typecons;

import consolecolors;
import toml;
import argd;

const string compiledAt = __TIMESTAMP__;
const string ENVMAN_VERSION = "0.0.1";
__gshared Instance instance;

struct Version {
	int major;
	int minor;
	int patch;

	static Version fromString(string s) {
		auto parts = s.split(".");

        Version v;
        if (parts.length > 0) v.major = parts[0].to!int;
        if (parts.length > 1) v.minor = parts[1].to!int;
        if (parts.length > 2) v.patch = parts[2].to!int;

        return v; 
	}
} 

struct Package {
	string name;
	string path;
	string pathKind;
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
		if ((pkgAlias in packages) !is null) {
			string path = packages[pkgAlias].str;
			if (path.startsWith("http://") || path.startsWith("https://")) {
				return tuple(true, Package(pkgAlias, path, "url"));
			}
			return tuple(true, Package(pkgAlias, path, "local"));
		}
		return tuple(false, Package.init);
	}

	Package[] getAllPackages() {
		Package[] list;
		auto packages = instance.getPackagesTable();
		foreach (pkgAlias, val; packages) {
			if (val.type == TOML_TYPE.STRING) {
				string path = val.str;
				string pathKind = (path.startsWith("http://") || path.startsWith("https://")) ? "url" : "local";
				list ~= Package(pkgAlias, path, pathKind);
			}
		}
		return list;
	}

	bool removePackage(string pkgAlias) {
		auto packages = instance.getPackagesTable();
		if ((pkgAlias in packages) !is null) {
			packages.remove(pkgAlias);
			instance.savePackagesTable(packages);
			return true;
		}
		return false;
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

	void saveConfig(ref TOMLDocument doc) {
		std.file.write(savePath, doc.toString());
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
}


class PathAppendCommand : Command {
	this() {
		super("append");
		description = "Append a directory or file path with a slug";
		usage = "<slug> <path>";
		argCollType = ArgCollectionType.exact;
		argCount = 2;
	}

	override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string slug = args[0];
		string pathArg = absolutePath(args[1]);

		try {
			auto paths = instance.getPathsTable();
			paths[slug] = TOMLValue(pathArg);
			instance.savePathsTable(paths);
		} catch (Exception e) {
			return CommandResult.error("Failed to save path: " ~ e.msg);
		}

		return CommandResult.ok("Appended " ~ slug ~ " -> " ~ pathArg);
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
			auto paths = instance.getPathsTable();
			if ((slug in paths) !is null) {
				paths.remove(slug);
				instance.savePathsTable(paths);
				return CommandResult.ok("Deleted " ~ slug);
			}
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

		if (hasOption("--open", "-o")) {
			executeShell("start \"\" \"" ~ path ~ "\"");
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

			bool found = false;
			foreach (key, val; paths) {
				if (key.toLower().canFind(query) || val.str.toLower().canFind(query)) {
					writeln(key ~ " = " ~ val.str);
					found = true;
				}
			}

			if (!found) {
				writeln("No matching paths found.");
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
			auto paths = instance.getPathsTable();
			if ((slug in paths) is null) {
				return CommandResult.error("Slug " ~ slug ~ " not found.");
			}
			paths[slug] = TOMLValue(pathArg);
			instance.savePathsTable(paths);
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
		registerSubCommand(new PathAppendCommand());
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

class PkgRegisterCommand : Command {
	this() {
		super("register");
		description = "Registers a file/directory as a package on global package registery";
		argCollType = ArgCollectionType.minimum;
		usage = "<package alias> <package path>";
		argCount = 2;
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string aliasName = args[0];
		string packagePath = args[1];

		string finalPath = packagePath;
		if (!finalPath.startsWith("http://") && !finalPath.startsWith("https://")) {
			finalPath = absolutePath(packagePath);
		}

		try {
			auto packages = instance.getPackagesTable();
			packages[aliasName] = TOMLValue(finalPath);
			instance.savePackagesTable(packages);
		} catch (Exception e) {
			return CommandResult.error("Failed to register package: " ~ e.msg);
		}

		return CommandResult.ok("Registered package " ~ aliasName ~ " -> " ~ finalPath);
	}
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

struct PackageConfig {
	string aliasName;
	string dest;
	string expectedType;
	string description;
	string obtainFrom;
}

PackageConfig[] parsePackagesEnvman(string targetDir, bool quiet, out bool success, out string errorMsg) {
	string envmanFile = buildPath(targetDir, "packages.envman");
	if (!exists(envmanFile)) {
		success = false;
		errorMsg = "No packages.envman found in " ~ targetDir;
		return null;
	}

	TOMLDocument doc;
	try {
		doc = parseTOML(readText(envmanFile));
	} catch (Exception e) {
		success = false;
		errorMsg = "Failed to parse packages.envman: " ~ e.msg;
		return null;
	}

	if ("packages" !in doc || doc["packages"].type != TOML_TYPE.TABLE) {
		success = false;
		errorMsg = "No valid [packages] table found in " ~ envmanFile;
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
			string[] parts;
			foreach(v; destNode.array) {
				if (v.type == TOML_TYPE.STRING) parts ~= v.str;
			}
			dest = buildPath(parts);
		} else if (destNode.type == TOML_TYPE.TABLE) {
			auto tbl = destNode.table;
			if ("path" in tbl) {
				if (tbl["path"].type == TOML_TYPE.STRING) {
					dest = tbl["path"].str;
				} else if (tbl["path"].type == TOML_TYPE.ARRAY) {
					string[] parts;
					foreach(v; tbl["path"].array) {
						if (v.type == TOML_TYPE.STRING) parts ~= v.str;
					}
					dest = buildPath(parts);
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

void installLocalPackage(PackageConfig cfg, string targetDir, Package pkg, bool quiet, bool isUpgrade) {
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

	if (isUpgrade) {
		if (!isSourceNewer(sourceUrlOrPath, absoluteDest)) {
			if (!quiet) cwritefln("Package <cyan>%s</cyan> is up to date.", cfg.aliasName);
			return;
		}
		if (!quiet) writeln("Upgrading ", cfg.aliasName, " from ", sourceUrlOrPath, " -> ", absoluteDest);
	} else {
		if (!quiet) writeln("Copying ", cfg.aliasName, " from ", sourceUrlOrPath, " -> ", absoluteDest);
	}
	try {
		copyRecursively(sourceUrlOrPath, absoluteDest);
	} catch (Exception e) {
		if (!quiet) writeln("Failed to copy package ", cfg.aliasName, ": ", e.msg);
	}
}

string hashFile(string path) {
	import std.digest.sha : SHA256;
	import std.digest : toHexString;
	import std.stdio : File;

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
	import std.stdio : File;

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

CommandResult processPackages(string[] args, bool quiet, bool isUpgrade) {
	string targetDir = args.length > 0 ? args[0] : ".";
	
	bool success;
	string errorMsg;
	PackageConfig[] configs = parsePackagesEnvman(targetDir, quiet, success, errorMsg);
	
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
			installLocalPackage(cfg, targetDir, pkg, quiet, isUpgrade);
		}
	}

	return CommandResult.ok(isUpgrade ? "Packages upgraded successfully" : "Packages installed successfully");
}

class PkgInstallCommand : Command {
	this() {
		super("install");
		description = "Installs packages from packages.envman into the current directory";
		argCollType = ArgCollectionType.minimum;
		usage = "[target directory path]";
		argCount = 0;
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		return processPackages(args, quiet, false);
	}
}

class PkgUpgradeCommand : Command {
	this() {
		super("upgrade");
		description = "Upgrades packages from packages.envman by checking if the source is modified";
		argCollType = ArgCollectionType.minimum;
		usage = "[target directory path]";
		argCount = 0;
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		return processPackages(args, quiet, true);
	}
}

class PkgCheckCommand : Command {
	this() {
		super("check");
		description = "Checks packages in packages.envman without installing";
		argCollType = ArgCollectionType.minimum;
		usage = "[target directory path]";
		argCount = 0;

		addOption("--fix", "-fix", "Removes unregistered (unknown) packages from packages.envman file");		
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string targetDir = args.length > 0 ? args[0] : ".";
		
		bool success;
		string errorMsg;
		PackageConfig[] configs = parsePackagesEnvman(targetDir, quiet, success, errorMsg);
		
		if (!success) {
			if (!quiet) cwritefln("<yellow>Notice:</yellow> Not using envman onefile in current directory, or failed to parse. (<red>%s</red>)", errorMsg);
			return CommandResult.ok();
		}

		if (!quiet) writefln("Status: envman onefile in use (%d packages defined).", configs.length);
		
		string[] unregistered;

		foreach (cfg; configs) {
			writefln("- Package: %s", cfg.aliasName);
			if (!instance.onefileMgr.isPackageExists(cfg.aliasName)) {
				cwritefln("  Status: [<red>Unregistered</red>] (Missing from global registry, use --fix to remove it from packages.envman)");
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
				string envmanFile = buildPath(targetDir, "packages.envman");
				try {
					TOMLDocument doc = parseTOML(readText(envmanFile));
					auto tbl = doc["packages"].table;
					foreach (aliasName; unregistered) {
						tbl.remove(aliasName);
					}
					doc["packages"] = TOMLValue(tbl);
					std.file.write(envmanFile, doc.toString());
					cwritefln("\nFixed: Removed <yellow>%d</yellow> unregistered package(s) from packages.envman.", unregistered.length);
				} catch (Exception e) {
					return CommandResult.error("Failed to fix packages.envman: " ~ e.msg);
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
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string packageName = args[0];
		if (!instance.onefileMgr.isPackageExists(packageName))
			return CommandResult.error(format("Could not found package `%s`", packageName));

		Tuple!(bool, Package) pkgResult = instance.onefileMgr.getPackage(packageName);
		Package pkg = pkgResult[1];
		if (!pkgResult[0]) return CommandResult.error("We have a a internal error. Looks like package exists in registery but the data doesnt loaded.");

		writefln("Package %s
\tLocation (Path): %s
\tLocation (Path) Type: %s", pkg.name, pkg.path, pkg.pathKind);
		return CommandResult.ok();
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

		if (!instance.onefileMgr.isPackageExists(aliasName)) {
			return CommandResult.error("Package '" ~ aliasName ~ "' does not exist in the global registry.");
		}

		try {
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
		description = "Adds a package requirement to packages.envman in the current directory";
		argCollType = ArgCollectionType.minimum;
		usage = "<package alias> <destination path>";
		argCount = 2;
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string aliasName = args[0];
		string destination = args[1];
		string envmanFile = "packages.envman";

		if (!instance.onefileMgr.isPackageExists(aliasName)) {
			return CommandResult.error("Package '" ~ aliasName ~ "' does not exist in the global registry.");
		}

		TOMLDocument doc;
		if (exists(envmanFile)) {
			try {
				doc = parseTOML(readText(envmanFile));
			} catch (Exception e) {
				return CommandResult.error("Failed to parse packages.envman: " ~ e.msg);
			}
		} else {
			doc = parseTOML("");
		}

		if ("packages" !in doc) {
			TOMLValue[string] emptyA;
			doc["packages"] = TOMLValue(emptyA);
		} else if (doc["packages"].type != TOML_TYPE.TABLE) {
			return CommandResult.error("Existing packages.envman has a invalid [packages] sector. Must be a table.");
		}

		auto tbl = doc["packages"].table;
		tbl[aliasName] = TOMLValue(destination);
		doc["packages"] = TOMLValue(tbl);

		try {
			std.file.write(envmanFile, doc.toString());
		} catch (Exception e) {
			return CommandResult.error("Failed to write to packages.envman: " ~ e.msg);
		}

		if (!quiet) cwritefln("Added <green>'%s'</green> -&gt; <green>'%s'</green> to packages.envman", aliasName, destination);
		return CommandResult.ok();
	}
}

class PkgDropCommand : Command {
	this() {
		super("drop");
		description = "Removes a package entry from packages.envman in the current directory";
		argCollType = ArgCollectionType.minimum;
		usage = "<package alias>";
		argCount = 1;
	}

	override CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		string aliasName = args[0];
		string envmanFile = "packages.envman";

		if (!exists(envmanFile)) {
			return CommandResult.error("No packages.envman found in current directory.");
		}

		TOMLDocument doc;
		try {
			doc = parseTOML(readText(envmanFile));
		} catch (Exception e) {
			return CommandResult.error("Failed to parse packages.envman: " ~ e.msg);
		}

		if ("packages" !in doc || doc["packages"].type != TOML_TYPE.TABLE) {
			return CommandResult.error("No valid [packages] table found in packages.envman.");
		}

		auto tbl = doc["packages"].table;
		if ((aliasName in tbl) is null) {
			return CommandResult.error("Package '" ~ aliasName ~ "' is not listed in packages.envman.");
		}

		tbl.remove(aliasName);
		doc["packages"] = TOMLValue(tbl);

		try {
			std.file.write(envmanFile, doc.toString());
		} catch (Exception e) {
			return CommandResult.error("Failed to write packages.envman: " ~ e.msg);
		}

		if (!quiet) cwritefln("Dropped <yellow>'%s'</yellow> from packages.envman.", aliasName);
		return CommandResult.ok();
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

© 2026", ENVMAN_VERSION, compiledAt);
		return CommandResult.ok();
	}
}
class RootCommand : Command {
	this() { 
		super("envman"); 
		description = format("Envman %s, environment/package manager", ENVMAN_VERSION);
		
		addOption("--verbose", "-v", "Enable verbose output");
		addOption("--quiet", "-q", "Suppress output");
		addOption("--gen-docs", "-gd", "Generate markdown documentation for all commands");
		addOption("--version", "-v", "Version of the envman");

		registerSubCommand(new PathSetCommand());
		registerSubCommand(new PathCommand());
		registerSubCommand(new PkgCommand());
		registerSubCommand(new InfoCommand());
	}

	override protected CommandResult onExecute(string[] args, bool verbose, bool quiet) {
		if (hasOption("--gen-docs", "-gd")) {
			std.file.write("DOCUMENTATION.md", buildMarkdown());
			cwritefln("<green>Documentation generation complete!</green> Saved to DOCUMENTATION.md");
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