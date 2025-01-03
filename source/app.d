module diedpi;

import std.conv;
import std.process : Pid;
import std.regex;
import std.stdio;

import core.sys.windows.winbase;
import core.sys.windows.wininet;
import core.sys.windows.winnt;

import core.sys.windows.wincon : FreeConsole;
import core.sys.windows.winuser : MessageBoxW, MB_ICONERROR;

import dfl.all;

import cfg;
import utils;
import mainform;
import network : configureInternet, closeInternet;
static import updater;
static import tools;

pragma(lib, "advapi32");
pragma(lib, "user32");
pragma(lib, "wininet");

void main(string[] args)
{
	import std.file : thisExePath, chdir, getcwd;
	import std.path : dirName;
	auto thispath = dirName(thisExePath());
	debug {
		writefln("Starting as %s in %s", thisExePath(), getcwd());
		writefln("Ready to switch path to %s", thispath);
    } else {
		if (!isRunningAsAdmin()) {
			writeln("false");
			MessageBoxW(null, "Программа должна быть запущена с правами администратора!\0"w.ptr, "Ошибка!\0"w.ptr, MB_ICONERROR);
			return;
		}
    }
	// При запуске schtasks зачем-то устанавливает cwd на C:\Windows\System32
	chdir(thispath);
	
	wstring mname = "DieDPI_Default_Mutex\0"w;
	auto mres = CreateMutexW(null, TRUE, mname.ptr);
	debug { } else {
		if (mres is null || GetLastError() == ERROR_ALREADY_EXISTS) {
			MessageBoxW(null, "Не может быть запущено больше одного экземпляра программы!\0"w.ptr, "Ошибка!\0"w.ptr, MB_ICONERROR);
			return;
		}
	}

	parseArgs(args);

	debug {
		LFLAGS.keepConsole = true;
    }

	if (!ConfigManager.initConfig()) {
		MessageBoxW(null, "Не удалось создать хранилище настроек!\0"w.ptr, "Ошибка!\0"w.ptr, MB_ICONERROR);
		return;
    }

	// На данный момент подразумеваем что ничто не сможет обновлять конфиг
	auto cfg = ConfigManager.getGlobalConfig();
	writefln("autostart: %d; persistentState: %d", cfg.autostart, cfg.persistentState);
	if (cfg.updateNeeded) {
		// Снимем флаг обновления, иначе будем бесконечно его гонять
		cfg.updateNeeded = false;
		ConfigManager.setUpdateNeeded(false);
		ConfigManager.writeConfig();
		updater.onCfgUpdateFlag();
		return;
    }
	
	// Консоль может понадобиться для разбора ошибок
	if(!LFLAGS.keepConsole || CONFIG.autostart) {
		FreeConsole();
    }
	try {
		if (LFLAGS.selfUpdateRun) {
			updater.selfUpdate();
			return;
        }
	} catch (Throwable ex) {
		printFormattedException(ex);
		return;
	}
	
	if (!configureInternet()) {
		MessageBoxW(null, "Не удалось настроить соединение с интернетом!\0"w.ptr, "Ошибка!\0"w.ptr, MB_ICONERROR);
		return;
	}
	scope(exit) closeInternet();
	
	// Подготовим себе нужные папки
	import std.file;
	foreach (dir; ["tools", "update"]) {
		// Если есть такой файл, удалим
		if (exists(dir) && !isDir(dir)) {
			remove(dir);
        }
		// Если такой папки нет, создадим
		if (!exists(dir)) {
			mkdir(dir);
        }
    }

	try {
		// Будем обновляться принудительно
		if (updater.selfUpdateNeeded()) {
			updater.downloadUpdate(false);
        }
		if (LFLAGS.updateOnly) {
			return;
        }
	} catch (Throwable ex) {
		printFormattedException(ex);
		return;
	}
	
	// С манифестом какая-то залупа, поэтому пока так
	Application.enableVisualStyles();
	import settingsform;
	auto mainForm = new MainForm();

	// Обновим
	cfg = ConfigManager.getGlobalConfig();
	if (cfg.autostart) {
		// Не открываем окно, но создаём Shell_NotifyIconW для кликабельной иконки в трее
    }

	Application.run(mainForm);

	// Остановим инструмент в обход persistentState
	tools.stopTool();

	// Запишем конфиг, в этом месте чтобы если после его изменений программа упадёт, следующий запуск будет со старым конфигом
	ConfigManager.writeConfig();

	if (LFLAGS.keepConsole) {
		cast(void) readln();
	}
}