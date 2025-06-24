module updater;

import std.conv;
import std.file;
import std.json;
import std.process;
import std.path;
import std.stdio;
import std.string;

import network;
import tools;
import utils : printFormattedException;

static import curl = std.net.curl;

// Config уже определён в std.process, так что импортируем только нужное
import cfg : ConfigManager, APP_VER;

void onCfgUpdateFlag() {
	// Костыль
	auto updateBat = File("update.bat", "w");
	// По задумке должен перезапускать спустя секунду
	updateBat.write(
"@echo off
timeout /t 1 /nobreak > NUL
del \"%~f0\" & cd /d update & start diedpi.exe -update"
	);
	updateBat.flush();
	updateBat.close();
	spawnShell(command: "update.bat > nul", config: std.process.Config(std.process.Config.Flags.detached));
}

void selfUpdate() {
	writeln("Running in updater mode");
	// Проверим что мы в папке update
	auto cwd = dirName(thisExePath());
	if (baseName(cwd) != "update") {
		writeln("Can't update from current directory");
		return;
    }
	foreach (entry; dirEntries(cwd, SpanMode.shallow)) {
		auto fname = baseName(entry.name);
		writeln("Copying file: " ~ fname);
		copy(entry.name, dirName(cwd) ~ "\\" ~ fname);
    }
	writeln("Done, cleaning up");
	auto cleanupBat = File("cleanup.bat", "w");
	// По задумке должен стартовать спустя 5 секунд, давая время программе выйти, и чистить текущую папку, в т.ч. удаляя себя
	cleanupBat.write(
"@echo off
timeout /t 5 /nobreak > NUL
cd /d \"%~dp0\"
for /F \"delims=\" %%i in ('dir /b') do (rmdir \"%%i\" /s/q > nul || del \"%%i\" /s/q > nul)
del \"%~f0\""
	);
	cleanupBat.flush();
	cleanupBat.close();
	spawnShell(command: "cleanup.bat > nul", config: Config(Config.Flags.detached));
	spawnProcess(program: "..\\diedpi.exe", config: Config(Config.Flags.detached));
}

bool goodbyeDPIUpdateNeeded() {
    writeln("Checking GoodbyeDPI updates");
    if (!verifyGoodbyeDPI()) {
        writeln("GoodbyeDPI is not installed");
        return false;
    }
    
    string installedVer = baseName(dirEntries(".\\tools\\goodbyedpi", SpanMode.shallow).front.name);
    writeln("GoodbyeDPI installed version is " ~ installedVer);
    string releases = getReleasesJSONCurl(TOOLS["GoodbyeDPI"w]);
    auto responseJSON = parseJSON(releases);
    auto latest = responseJSON[0];
    auto ver = latest["name"].get!string;
    writeln("GoodbyeDPI remote version is " ~ ver);

    return installedVer != ver;
}

bool zapretUpdateNeeded() {
    writeln("Checking Zapret updates");
    if (!verifyZapret()) {
        writeln("Zapret is not installed");
        return false;
    }
    
    string installedVer = baseName(dirEntries(".\\tools\\zapret", SpanMode.shallow).front.name);
    writeln("Zapret installed version is " ~ installedVer);
    string releases = getReleasesJSONCurl(TOOLS["Zapret"w]);
    auto responseJSON = parseJSON(releases);
    auto latest = responseJSON[0];
    auto ver = latest["name"].get!string;
    writeln("Zapret remote version is " ~ ver);

    return installedVer != ver;
}

bool isUpdateNeeded(uint timeout = 15) {
    try {
        auto result = curl.get(to!string(verURL));//curlOpenPage(to!string(verURL), timeout);
        //writefln("Version check request finished with HTTP code %d", result.code);
        string page = result.idup;//result.data;
        debug {
            writefln("Version check data according to curl:\n\"%s\"", page);
        }
        if (page.length < 1 /*|| result.code >= 400*/) {
            return false;
        }
        return internal__checkUpdatePage(page);
    } catch (Exception ex) {
        printFormattedException(ex);
        return false;
    }
}

bool selfUpdateNeeded() {
	import core.sys.windows.winbase;
	import core.sys.windows.wininet;

	auto page = openPage(verURL, updHeaders);
	if (page is null) {
		return false;
    }
	scope(exit) InternetCloseHandle(page);

	// Несмотря на то, что в файле число, получаем мы его текстом, а uint.max - 10 цифр
	// Так как здесь единственное место, где мы не читаем JSON, то продублируем здесь логику из network
	char[10] buf;
	uint bytenum = 0;
	auto responseResult = InternetReadFile(page, buf.ptr, 10, &bytenum);
	if (!responseResult) {
		writefln("InternetReadFile failed: 0x%08X", GetLastError());
    }

    return internal__checkUpdatePage(buf.idup);
    /*
	uint remoteVer = APP_VER;
	try {
		string sbuf = "";
		// Почистим строку от всякого мусора, который будет вызывать ConvException
		foreach (c; buf) {
			if (c == '\n' || c == ' ') {
				break;
            }
			sbuf ~= c;
        }
		//string verText = replaceAll(sbuf, ctrNotNumbers, "");
		remoteVer = to!uint(sbuf);
	} catch (Exception ex) {
		printFormattedException(ex);
    }
	// Подразумеваем не только что версия может расти, но и что может быть откат
	return APP_VER != remoteVer;
    */
}

private bool internal__checkUpdatePage(string page) {
    string buf;
    debug {
        writefln("Reading update data from page \"%s\"", page);
    }
    // Если в ответ пришло что-то капец длинное, то не будем это обрабатывать полностью
    if (page.length > 10) {
        buf = page[0..10];
    } else {
        buf = page;
    }
    uint remoteVer = APP_VER;
	try {
        debug {
            writefln("Cleaning up \"%s\"", buf);
        }
		string sbuf = "";
		// Почистим строку от всякого мусора, который будет вызывать ConvException
		foreach (c; buf) {
			if (c == '\n' || c == ' ') {
				break;
            }
			sbuf ~= c;
        }
		//string verText = replaceAll(sbuf, ctrNotNumbers, "");
        debug {
            writefln("Parsing remote version from \"%s\"", buf);
        }
		remoteVer = to!uint(sbuf);
	} catch (Exception ex) {
		printFormattedException(ex);
    }
	// Подразумеваем не только что версия может расти, но и что может быть откат
	return APP_VER != remoteVer;
}

bool downloadUpdate(bool force = false) {
	import std.json;
	import std.file;
	import std.string;

	try {
		string responseCache = getReleasesJSON(relURL);
		if (responseCache.length < 1) {
			return false;
        }

		import std.json;
		import std.file;
		import std.path;
		auto latest = parseJSON(responseCache)[0];
		//writeln(json[0]["zipball_url"]);
		auto ver = latest["name"].get!string;
		//auto publishedAt = latest["published_at"];
		wstring zipUrl = ""w;
		foreach (entry; latest["assets"].array) {
			string n = entry["name"].get!string;
			if (n == "update.zip") {
				zipUrl = to!wstring(entry["browser_download_url"].get!string);
            }
        }
		if (zipUrl == ""w) {
			writeln("Could not find update.zip in release " ~ ver);
			return false;
        }
		if (!exists("update\\" ~ ver ~ ".zip")) {
			writeln("Downloading DieDPI update");
			try {
				downloadAndExtract(zipUrl, ".\\update", ver);
            } catch (Exception ex) {
				import dfl.messagebox;
				printFormattedException(ex);
				msgBox("Ошибка обновления!"w, "Ошибка!"w, MsgBoxButtons.OK, MsgBoxIcon.ERROR);
				return false;
            } finally {
				remove("update\\" ~ ver ~ ".zip");
            }
        }
		foreach (entry; dirEntries("update/inst", SpanMode.shallow)) {
			auto fname = baseName(entry.name);
			writeln("Copying file: " ~ fname);
			copy(entry.name, "update\\" ~ fname);
        }
		rmdirRecurse("update\\inst");

		ConfigManager.setUpdateNeeded(true);
		ConfigManager.writeConfig();
	} catch (Throwable ex) {
		// По какой-то причине, если делать запросы циклом, на 17-й раз в responseCache всё кривое
		printFormattedException(ex);
		return false;
	}

	return true;
}