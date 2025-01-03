module cfg;

import std.conv : text;
import std.stdio;

import utils;
import tools : goodbyeDpiDefaultCommand;

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
const uint APP_VER = 0;

struct Config {
	bool autostart = false;
	bool persistentState = false;
	bool updateNeeded = false;
	uint configVer = 1;
	ubyte tool = 1; // В порядке следования в массиве tools.TOOLS
	int goodbyedpiKey = 9; // Должен меняться вручную и через автонастройку
	string[] zapretImplodedCommand = []; // Если автонастройка дала результаты, здесь сохраним его
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

	Config getGlobalConfig() {
		return CONFIG;
	}

	void setGlobalConfig(Config c) {
		CONFIG = c;
	}

	bool initConfig() {
		import std.file;
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
				Config[1] c;
				cfgFile.rawRead(c);
				setGlobalConfig(c[0]);
				writeln(CONFIG.configVer);
				cfgFile.close();

				// Заполним нужное прочитанными настройками
				goodbyeDpiDefaultCommand[0] = "-" ~ text(c[0].goodbyedpiKey);

				return true;
			}
		} catch (Exception ex) {
			printFormattedException(ex);
			return false;
		}
	}

	bool writeConfig() {
		import std.file;
		try {
			auto cfgFile = File("config.dat", "w+b");
			// Синхронизируем, несмотря на то, что это чтение
			synchronized {
				cfgFile.rawWrite((&CONFIG)[0..1]);
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