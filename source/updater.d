module updater;

import std.conv;
import std.file;
import std.process;
import std.path;
import std.stdio;
import std.string;

import network;
import utils : printFormattedException;

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
}

void downloadUpdate(bool force = false) {
	import std.json;
	import std.file;
	import std.string;

	try {
		string responseCache = getReleasesJSON(relURL);
		if (responseCache.length < 1) {
			return;
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
			return;
        }
		if (!exists("update\\" ~ ver ~ ".zip")) {
			writeln("Downloading DieDPI update");
			try {
				downloadAndExtract(zipUrl, ".\\update", ver);
            } catch (Exception ex) {
				import dfl.messagebox;
				printFormattedException(ex);
				msgBox("Ошибка обновления!"w, "Ошибка!"w, MsgBoxButtons.OK, MsgBoxIcon.ERROR);
				return;
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
		return;
	}

	return;
}