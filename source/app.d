module diedpi;

import std.array;
import std.conv;
import std.file : exists;
import std.process : Pid;
import std.regex;
import std.stdio;
import std.string;

//import core.sys.windows.windows;
import core.sys.windows.winbase;
import core.sys.windows.wininet;
import core.sys.windows.winnt;
import core.sys.windows.wtsapi32;

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
pragma(lib, "wtsapi32");

// Для корректной линковки libcurl
pragma(lib, "crypt32");
pragma(lib, "iphlpapi");
pragma(lib, "secur32");

import std.traits;
import etc.c.curl;
static foreach (func; __traits(allMembers, etc.c.curl)) {
    static if (isFunction!(__traits(getMember, etc.c.curl, func))) {
        pragma(linkerDirective, "/EXPORT:" ~ func);
    }
}

void killTools() {
    WTS_PROCESS_INFOW[] infos;
    WTS_PROCESS_INFOW* infosptr;
    uint procs = 0;
    auto res = WTSEnumerateProcessesW(WTS_CURRENT_SERVER_HANDLE, 0, 1, &infosptr, &procs);
    if (res == 0) {
        writeln("WTSEnumerateProcessesW had error 0x%08X", GetLastError());
        return;
    }
    infos = infosptr[0..procs];
    writefln("Got %d processes", procs);
    foreach (info; infos) {
        auto procName = fromStringz(info.pProcessName[0..255]).idup;
        if (procName == "goodbyedpi.exe"w || procName == "winws.exe"w) {
            writefln("Killing %s", procName);
            auto hProcess = OpenProcess(PROCESS_TERMINATE, 0, info.ProcessId);
            if (hProcess) {
                TerminateProcess(hProcess, 0);
            }
        }
    }
}

void main(string[] args) {
    try {
        
        debug {
            auto res = GetProcAddress(GetModuleHandle(null), "curl_global_init");
            writeln(res);
            if (res is null) {
                writeln("No curl_global_init found");
            } else {
                writeln("Found curl_global_init");
            }
        }
    
    
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
            writefln("Update needed according to the config");
            // Снимем флаг обновления, иначе будем бесконечно его гонять
            cfg.updateNeeded = false;
            ConfigManager.setUpdateNeeded(false);
            ConfigManager.writeConfig();
            if (exists("./update/diedpi.exe")) {
                updater.onCfgUpdateFlag();
                return;
            } else {
                writefln("Files missing, aborting update");
            }
        }
        
        // Консоль может понадобиться для разбора ошибок
        if(!LFLAGS.keepConsole) {
            FreeConsole();
        }
        try {
            if (LFLAGS.selfUpdateRun) {
                debug {
                    writeln("Self-updating from LFLAGS");
                }
                updater.selfUpdate();
                return;
            }
        } catch (Throwable ex) {
            printFormattedException(ex);
            return;
        }
        
        debug {
            writeln("Configuring WinINet");
        }
        if (!configureInternet()) {
            MessageBoxW(null, "Не удалось настроить соединение с интернетом!\0"w.ptr, "Ошибка!\0"w.ptr, MB_ICONERROR);
            return;
        }
        scope(exit) closeInternet();
        
        debug {
            writeln("Checking work dirs");
        }
        // Подготовим себе нужные папки
        import std.file;
        foreach (dir; ["tools", "update"]) {
            // Если есть такой файл, удалим
            if (exists(dir) && !isDir(dir)) {
                debug {
                    writefln("Removing obstructing file %s", dir);
                }
                remove(dir);
            }
            // Если такой папки нет, создадим
            if (!exists(dir)) {
                debug {
                    writefln("Creating missing folder %s", dir);
                }
                mkdir(dir);
            }
        }

        try {
            // Будем обновляться принудительно
            if (updater.isUpdateNeeded(2)) {
                debug {
                    writeln("Update found on launch, downloading update");
                }
                updater.downloadUpdate(false);
            }
            if (LFLAGS.updateOnly) {
                return;
            }
        } catch (Throwable ex) {
            printFormattedException(ex);
            return;
        }

        // Бывает так, что программа падает, а инструмент остаётся, и его надо завершать вручную
        writeln("Checking and killing potentially running tools");
        killTools();
        
        // С манифестом какая-то залупа, поэтому пока так
        Application.enableVisualStyles();
        import settingsform;
        auto mainForm = new MainForm();

        // Обновим
        cfg = ConfigManager.getGlobalConfig();
        if (cfg.autostart) {
            // Не открываем окно, но создаём Shell_NotifyIconW для кликабельной иконки в трее
        }

        debug {
            writeln("Creating window");
        }
        Application.run(mainForm);

        // Остановим инструмент в обход persistentState
        tools.stopTool();

        // Запишем конфиг, в этом месте чтобы если после его изменений программа упадёт, следующий запуск будет со старым конфигом
        ConfigManager.writeConfig();

        if (LFLAGS.keepConsole) {
            cast(void) readln();
        }
    } catch (Throwable t) {
        printFormattedException(t);
    }
}