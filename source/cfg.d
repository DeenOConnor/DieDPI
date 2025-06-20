module cfg;

import std.conv : text;
import std.stdio;

import utils;
import tools : goodbyeDpiDefaultCommand, zapretDefaultCommand;

struct LaunchFlags {
	bool selfUpdateRun = false;
	bool keepConsole = false;
	bool autosetupOnly = false;
	bool downloadOnly = false;
	bool updateOnly = false;
	bool addServiceOnly = false;
	bool removeServiceOnly = false;
}

LaunchFlags LFLAGS;

// Должно быть зашито в файл
const uint APP_VER = 1;

struct ConfigV2 {
	ushort magic = 4517;
	uint configVer = 2;
	bool autostart = false;
	bool persistentState = false;
	bool updateNeeded = false;
	bool autoUpdate = true;
	ubyte tool = 1;
	int goodbyedpiKey = 9;
	string[] zapretCommand = [];
    string verURL = "";
    string updateURL = "";
	// TODO : Реализовать
}

struct Config {
	bool autostart = false;
	bool persistentState = false;
	bool updateNeeded = false;
	uint configVer = 1;
	ubyte tool = 1; // В порядке следования в массиве tools.TOOLS
	int goodbyedpiKey = 9; // Должен меняться вручную и через автонастройку
	string[] zapretCommand = []; // Если автонастройка дала результаты, здесь сохраним его
}

private struct Config_store {
	bool a;
	bool p;
	bool u;
	uint v;
	ubyte t;
	int g;
	size_t zl;
}

// Я так и не понял как правильно манипулировать shared(), поэтому просто синхронизируем обращения
__gshared Config CONFIG;

// Для контроля поточности будем все операции производить через этот класс
synchronized class ConfigManager {
	
static:

	void setAutostart(bool as) {
		CONFIG.autostart = as;
    }

	void setPersistentState(bool ps) {
		CONFIG.persistentState = ps;
    }

	void setUpdateNeeded(bool un) {
		CONFIG.updateNeeded = un;
    }

	void setTool(ubyte t) {
		writefln("Selected tool %d", t);
		CONFIG.tool = t;
    }
	
	void setGoodbyeDpiKey(int k) {
		CONFIG.goodbyedpiKey = k;
    }

	void setZapretCommand(string[] c) {
		CONFIG.zapretCommand = c.dup;
    }

	Config getGlobalConfig() {
		return CONFIG;
	}

	void setGlobalConfig(Config c) {
		CONFIG = c;
	}

	bool initConfig() {
		import std.file;
		import std.array : split;
		try {
			if (!exists("config.dat")) {
				// Если запускаемся в режиме обновления, создавать файл конфига не нужно
				if (!LFLAGS.selfUpdateRun) {
					writeConfig();
				}
				return true;
			} else {
				auto cfgFile = File("config.dat", "r+b");
				// Так делать плохо и всё такое, но мне пофиг, я томат
				Config_store[1] c;
				cfgFile.rawRead(c);
				Config cfg;
				cfg.autostart = c[0].a;
				cfg.persistentState = c[0].p;
				cfg.updateNeeded = c[0].u;
				cfg.configVer = c[0].v;
				cfg.tool = c[0].t;
				cfg.goodbyedpiKey = c[0].g;
				if (c[0].zl > 0) {
					// Считаем что дальше идёт команда для zapret
					char[] str = new char[c[0].zl];
					cfgFile.rawRead(str);
					if (str.length != 0) {
						cfg.zapretCommand = str.idup.split(" ");
                    }
                }

				setGlobalConfig(cfg);
				writeln(CONFIG.configVer);
				cfgFile.close();

				// Заполним нужное прочитанными настройками
				goodbyeDpiDefaultCommand[0] = "-" ~ text(cfg.goodbyedpiKey);
				if (cfg.zapretCommand.length > 0) {
					// В команде не учитываем путь до исполняемого файла
					zapretDefaultCommand = zapretDefaultCommand[0] ~ cfg.zapretCommand;
                }

				return true;
			}
		} catch (Exception ex) {
			printFormattedException(ex);
			return false;
		}
	}

	bool writeConfig() {
		import std.file;
		import std.array : join;
		try {
			auto cfgFile = File("config.dat", "w+b");
			Config_store c;
			string zc = "";
			// Синхронизируем, несмотря на то, что это чтение
			synchronized {
				c.a = CONFIG.autostart;
				c.p = CONFIG.persistentState;
				c.u = CONFIG.updateNeeded;
				c.v = CONFIG.configVer;
				c.t = CONFIG.tool;
				c.g = CONFIG.goodbyedpiKey;
				if (CONFIG.zapretCommand.length > 0) {
					zc = CONFIG.zapretCommand.join(" ");
					c.zl = zc.length;
                }
			}
			cfgFile.rawWrite((&c)[0..1]);
			if (zc.length > 0) {
				cfgFile.rawWrite(zc);
            }
			cfgFile.flush();
			cfgFile.close();
			return true;
		} catch (Exception ex) {
			printFormattedException(ex);
			return false;
		}
	}

}