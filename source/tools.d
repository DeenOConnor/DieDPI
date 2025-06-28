module tools;

import std.array;
import std.conv;
import std.file;
import std.json;
import std.process;
import std.stdio;
import std.string;
import std.typecons;

// Для совсем отбитых случаев будем вызывать Application.onThreadException
import dfl.application;

import cfg : ConfigManager, LFLAGS;
import network;
import utils : printFormattedException;

// Обращения к нему должны синхронизироваться!
// Пока что эта штука просто тут валяется, но ей по-хорошему нужен следящий поток
// На случай если программа завершится не из-за действий пользователя
// В такой ситуации правильнее было бы, думаю, хотя бы диалоговое окно показать
private __gshared Pid currentTool;

// Это лучше заполнять из какого-нибудь конфига
const auto TOOLS = [
	// Один из последних релизов GoodbyeDPI помечен как пре-релиз, и поэтому по ссылке на latest открывается устаревший
	"GoodbyeDPI"w: "https://api.github.com/repos/ValdikSS/GoodbyeDPI/releases"w,
	// Несмотря на наличие zapret-win-bundle, бинари проще скачать из релизов основного репозитория
	"Zapret"w: "https://api.github.com/repos/bol-van/zapret/releases"w,
	// Надо подумать актуально ли ByeDPI
	// Потенциально тем, у кого общий комп, и не получится гонять софт от админа
	// Тогда встаёт вопрос как в автоматическом режиме задавать прокси при включении обхода
	// Вроде можно через InternetSetOption, задавая значение PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY
	// Нужно будет проверить, но только если это будет действительно актуально
	// "ByeDPI"w: "https://api.github.com/repos/hufrea/byedpi/releases\0"w,
];

auto goodbyeDpiDefaultCommand = [
	"-9",
	"--dns-addr", "77.88.8.8",
	"--dns-port", "1253",
	"--dnsv6-addr", "2a02:6b8::feed:0ff",
	"--dnsv6-port", "1253",
];

// Войс в discord не работает, если убрать --dpi-desync-fooling=badseq, --dpi-desync-any-protocol, --dpi-desync-cutoff=d3 или fake-quic и fake-tls
// На МТС работает без fake-tls, а ещё работает с fooling=md5sig, но у некоторых не работает, а у некоторых наоборот только так и работает
// Вообще эта штука должна работать +- для всех
auto zapretDefaultCommand = [
	// Т.к. запускаться zapret будет из заранее неизвестной папки, подставим её на место %DIR%
	"%DIR%winws.exe",
	"--wf-tcp=80,443",
	"--wf-udp=80,443,50000-65535",
	"--dpi-desync-fooling=md5sig",
	"--dpi-desync=fakedsplit",
	"--dpi-desync-split-pos=method+2",
	"--dpi-desync-udplen-increment=12",
	"--dpi-desync-udplen-pattern=0xF00F",
	"--dpi-desync-any-protocol=1",
	"--dpi-desync-cutoff=d3",
	// И тут тоже
	"--dpi-desync-fake-tls=%DIR%tls_clienthello_www_google_com.bin",
	"--dpi-desync-fake-quic=%DIR%quic_initial_www_google_com.bin"
];

private Pid synchronizedToolAccessor(bool op = false, Pid newVal = null) {
	//synchronized {
		// true = запись
		if (op) {
			currentTool = newVal;
		}
		return currentTool;
	//}
}

Pid getCurrentTool() {
	return synchronizedToolAccessor();
}

void setCurrentTool(Pid newPid) {
	synchronizedToolAccessor(true, newPid);
}

bool startTool() {
	final switch (ConfigManager.getGlobalConfig().tool) {
		case 0:
			writeln("Starting GoodbyeDPI");
			return startGoodbyeDPI();
		case 1:
			writeln("Starting Zapret");
			return startZapret();
    }
}

bool stopTool() {
	import core.time : dur;
	try {
		auto pid = synchronizedToolAccessor();
		if (pid is null) {
			// Даже не запускался
			return true;
		}
		auto pStatus = tryWait(pid);
		if (pStatus.terminated) {
			// Уже не работает
			return true;
		}
		kill(pid);
		pStatus = waitTimeout(pid, dur!"seconds"(1));
		if (pStatus.terminated) {
			return true;
		}
	} catch (Exception ex) {
		printFormattedException(ex);
		// Ситуация критичная, напугаем пользователя
		Application.onThreadException(ex);
    }

	// Скорее всего, он завершится рано или поздно
	return false;
}

bool verifyGoodbyeDPI() {
	debug {
		import std.path : absolutePath;
		writefln("Looking for GoodbyeDPI in %s", absolutePath(".\\tools\\goodbyedpi"));
    }
	if (!exists(".\\tools\\goodbyedpi")) {
		writeln("GoodbyeDPI is not installed");
		return false;
    }

	auto toolpath = dirEntries(".\\tools\\goodbyedpi", SpanMode.shallow).front.name;

	auto reqFiles = [
		"goodbyedpi.exe",
		"WinDivert64.sys",
		"WinDivert.dll"
	];
	foreach (reqFile; reqFiles) {
		if (
			!exists(toolpath ~ "\\" ~ reqFile)
			|| isDir(toolpath ~ "\\" ~ reqFile)
		) {
			return false;
		}
    }

	return true;
}

bool startGoodbyeDPI() {
	if (!verifyGoodbyeDPI()) {
		import dfl.base;
		import dfl.messagebox;
		auto res = msgBox("Выбранный инструмент для обхода не установлен, установить?"w, "Внимание!"w, MsgBoxButtons.YES_NO, MsgBoxIcon.QUESTION);
		writefln("DialogResult %d", cast(ubyte)res);
		if (res != DialogResult.YES && res != DialogResult.OK) {
			// Если юзер не хочет, забьём
			return false;
        }
		bool dlRes = downloadGoodbyeDPI();
		if (!dlRes) {
			msgBox("Не удалось установить инструмент\nПопробуйте снова, и, если ошибка сохранится, сообщите об этом"w, "Ошибка!"w, MsgBoxButtons.OK, MsgBoxIcon.ERROR);
			return false;
        }
		return startGoodbyeDPI();
    }

	auto currentPid = synchronizedToolAccessor();
	if (currentPid !is null) {
		auto pStatus = tryWait(currentPid);
		if (!pStatus.terminated) {
			// Какой-то инструмент уже работает
			return false;
		}
	}

	try {
		auto toolpath = dirEntries(".\\tools\\goodbyedpi", SpanMode.shallow).front.name ~ "\\goodbyedpi.exe";
		auto cmd = toolpath ~ goodbyeDpiDefaultCommand;
        debug {
            writefln("Using command \"%s\"", cmd);
        }
		auto pid = spawnProcess(cmd, config: Config(Config.Flags.suppressConsole));

		import core.time : dur;
		auto pStatus = waitTimeout(pid, dur!"seconds"(1));
		if (pStatus.terminated) {
			import dfl.base;
			import dfl.messagebox;
			writeln("GoodbyeDPI didn't properly start after a second, assuming error");
			msgBox("Не удалось запустить инструмент, сообщите об этой ошибке\n\nЕсли инструмент не работает, можно попробовать выбрать другой в настройках!"w, "Ошибка!"w, MsgBoxButtons.OK, MsgBoxIcon.ERROR);
			return false;
		}

		synchronizedToolAccessor(true, pid);
		return true;
	} catch (Exception ex) {
		printFormattedException(ex);
		debug {
			Application.onThreadException(ex);
        }
		return false;
    }
}

bool verifyZapret() {
	debug {
		import std.path : absolutePath;
		writefln("Looking for Zapret in %s", absolutePath(".\\tools\\zapret"));
    }
	if (!exists(".\\tools\\zapret")) {
		writeln("Zapret is not installed");
		return false;
    }

	auto toolpath = dirEntries(".\\tools\\zapret", SpanMode.shallow).front.name;

	auto reqFiles = [
		"winws.exe",
		"WinDivert64.sys",
		"WinDivert.dll",
		"cygwin1.dll",
		"quic_initial_www_google_com.bin",
		"tls_clienthello_www_google_com.bin"
	];
	foreach (reqFile; reqFiles) {
		if (
			!exists(toolpath ~ "\\" ~ reqFile)
			|| isDir(toolpath ~ "\\" ~ reqFile)
		) {
			// Не запускаемся если чего-то не хватает
			return false;
		}
    }
	
	return true;
}

bool startZapret() {
	if (!verifyZapret()) {
		import dfl.base;
		import dfl.messagebox;
		auto res = msgBox("Выбранный инструмент для обхода не установлен, установить?"w, "Внимание!"w, MsgBoxButtons.YES_NO, MsgBoxIcon.QUESTION);
		writefln("DialogResult %d", cast(ubyte)res);
		if (res != DialogResult.YES && res != DialogResult.OK) {
			// Если юзер не хочет, забьём
			return false;
        }
		bool dlRes = downloadZapret();
		if (!dlRes) {
			msgBox("Не удалось установить инструмент\nПопробуйте снова, и, если ошибка сохранится, сообщите об этом"w, "Ошибка!"w, MsgBoxButtons.OK, MsgBoxIcon.ERROR);
			return false;
        }
		return startZapret();
    }

	auto currentPid = synchronizedToolAccessor();
	if (currentPid !is null) {
		auto pStatus = tryWait(currentPid);
		if (!pStatus.terminated) {
			// Какой-то инструмент уже работает
			return false;
		}
	}

	import std.path : absolutePath;

	auto folder = dirEntries(".\\tools\\zapret", SpanMode.shallow).front.name;
	// Это уже не нужно, но оставлю на всякий
	//auto toolpath = folder ~ "\\winws.exe";
	//folder = absolutePath(folder);
	// Я скачал 100% GC, я буду использовать его на 100%
	//auto cmd = toolpath ~ zapretDefaultCommand;
    auto cmd = zapretDefaultCommand.dup;
	foreach (ind; 0 .. cmd.length) {
		// В параметры где указаны файлы, подставим путь до них
		if (indexOf(cmd[ind], '%') >= 0) {
			cmd[ind] = replace(cmd[ind], "%DIR%", folder ~ "\\");
        }
    }

	try {
        debug {
            writefln("Using command \"%s\"", cmd);
        }
		auto pid = spawnProcess(cmd, config: Config(Config.Flags.suppressConsole)); //, File("stdin.txt", "r"), File("stdout.txt", "w"), File("stderr.txt", "w"));

		import core.time : dur;
		auto pStatus = waitTimeout(pid, dur!"seconds"(1));
		if (pStatus.terminated) {
			import dfl.base;
			import dfl.messagebox;
			writeln("Zapret didn't properly start after a second, assuming error");
			msgBox("Не удалось запустить инструмент, сообщите об этой ошибке\n\nЕсли инструмент не работает, можно попробовать выбрать другой в настройках!"w, "Ошибка!"w, MsgBoxButtons.OK, MsgBoxIcon.ERROR);
			return false;
		}

		synchronizedToolAccessor(true, pid);
		return true; 
    } catch (Exception ex) {
		printFormattedException(ex);
		debug {
			Application.onThreadException(ex);
        }
		return false;
    }
}

// По идее GoodbyeDPI - это должен быть "стандатный" вариант, особенно когда он наконец научится работать с UDP
bool autosetupGoodbyeDPI(uint tries = 5, void function() progressTick = { return; }) {
	if (!verifyGoodbyeDPI()) {
		return false;
    }

	stopTool();

	if (!exists("stdin.txt") || isDir("stdin.txt")) {
		auto f = File("stdin.txt", "w");
		f.close();
	}

	auto toolpath = dirEntries(".\\tools\\goodbyedpi", SpanMode.shallow).front.name;

	auto command = [
		toolpath ~ "\\goodbyedpi.exe",
		"-5",
		"--dns-addr", "77.88.8.8",
		"--dns-port", "1253",
		"--dnsv6-addr", "2a02:6b8::feed:0ff",
		"--dnsv6-port", "1253",
		// Сайты банятся как попало, в т.ч. без постановления и внесения в реестр, так что не вижу смысла вести списки 
		// "--blacklist", "..\\russia-blacklist.txt",
		// "--blacklist", "..\\russia-youtube.txt"
	];

	long time = long.max;
	int key;
	foreach (int i; 5..10) {
		command[1] = "-" ~ text(i);
		auto proc = spawnProcess(command, File("stdin.txt", "r"), File("stdout.txt", "w"), File("stderr.txt", "w"), config: Config(Config.Flags.suppressConsole));
		//MessageBoxW(null, "GoodbyeDPI запущен\0"w.ptr, "\0"w.ptr, 0);
		auto avg = rankConnection(tries, LFLAGS.keepConsole, progressTick);
		if (avg < 0) {
			// Что-то косячит, валим
			return false;
        }
		writefln("Trying GoodbyeDPI with -%d resulted in avg %d", i, avg);
		if (avg < time) {
			time = avg;
			key = i;
		}
		kill(proc);
		stdout.flush();
	}
	writefln("Best response time %d with key -%d", time, key);
	// Обновим подобранные настройки
	ConfigManager.setGoodbyeDpiKey(key);
	goodbyeDpiDefaultCommand[0] = "-" ~ text(key);
	return true;
}

bool autosetupZapret(uint tries = 3, void function() progressTick = { return; }) {
	if (!verifyZapret()) {
		return false;
    }
	//return true;
	stopTool();

	auto toolpath = dirEntries(".\\tools\\zapret", SpanMode.shallow).front.name;

	// Тут не смотрим на 80 порт, но я не уверен что у всех провайдеров можно на него забить
	// Пока что, вроде, все, у кого проверяли, разницы не ощутили
	auto baseCommand = [
		toolpath ~ "\\winws.exe",
		"--wf-tcp=80,443", // "--wf-tcp=80,443",
		"--wf-udp=80,443,50000-65535", // "--wf-udp=80,443,50000-65535",
        "--dpi-desync-split-pos=method+2",
        "--dpi-desync-udplen-increment=12",
        "--dpi-desync-udplen-pattern=0xF00F",
        "--dpi-desync-any-protocol=1",
		//"--dpi-desync-fake-tls=\"tls_clienthello_www_google_com.bin\"",
		// Надо попробовать вычислять количество узлов провайдера через tracert и указывать TTL так
		// "--dpi-desync-ttl=4"
	];

	// Т.к. у zapret нереально много параметров, будем пробовать перебирать режимами
	auto modes = [
		1: [
			"--dpi-desync=": ["fake,split", "fake,split2", "fakedsplit"], // По-моему не получится сюда приткнуть disorder, хотя он работает неплохо
			"--dpi-desync-fooling=": ["badseq", "md5sig"], // Дискорд лучше всего себя чувствует с badseq, но md5sig тоже помогает
			"--dpi-desync-cutoff=": ["d2", "d3"], // Я уже не помню почему именно 2 и 3
			"--dpi-desync-fake-tls=" : ["", toolpath ~ "\\tls_clienthello_www_google_com.bin"] // На МТС поддельный clienthello всё только портит
		],
		2: [
			"--dpi-desync=": ["fakedsplit", "fake,split2"],
            "--dpi-desync-fooling=": ["md5sig"],
			"--dpi-desync-repeats=": ["3", "7", "19"],
            "--dpi-desync-cutoff=": ["d3"],
            "--dpi-desync-fake-tls=" : ["", toolpath ~ "\\tls_clienthello_www_google_com.bin"],
            "--dpi-desync-fake-quic=" : ["", toolpath ~ "\\quic_initial_www_google_com.bin"]
		]
	];


	foreach (i, mode; modes) {

		if (mode.length < 2) {
			continue;
		}

		// По сути, baseCommand и так должен работать норм, но парочку опций может потребоваться изменить
		// Поэтому смотритм на те, по которым больше одного варианта, и пробуем их комбинировать

		string[] variants;
		string[] fixed;

		// Соберём все варианты в куски команд, которые можно будет подставить
		foreach (opt, vals; mode) {
			if (vals.length == 1) {
				fixed ~= opt ~ vals[0];
			} else {
				if (variants.length == 0) {
					foreach (val; vals) {
						auto optval = val == "" ? "" : opt ~ val;
						variants ~= optval;
					}
				} else {
					import std.algorithm.iteration;
					
					string[] variantsBuf;
					foreach (variant; variants) {
						variantsBuf ~= vals.map!(delegate(v) {
							if (v == "") {
								return variant;
							}
							v = variant ~ " " ~ opt ~ v;
							return v;
						}).array;
					}
					variants = variantsBuf.dup;

					/*
					foreach (val; vals) {
						// Если значение пустое, то не используем опцию
						auto optval = val == "" ? "" : opt ~ val;
						variants = variants.map!(delegate (v) {
							writefln(v);
							v = optval ~ " " ~ v;
							writefln(v);
							return v;
						}).array;
					}
					*/
				}
			}
		}

		long time = long.max;
		size_t key;
		foreach (j, variant; variants) {
			auto command = baseCommand ~ fixed ~ split(variant, " ");
			writefln("Testing zapret command:\n'%s'", join(command, " "));
			// Теперь, когда у нас есть собранная команда, можем попытаться запустить zapret и проверить помогло ли
			auto proc = spawnProcess(command, File("stdin.txt", "r"), File("stdout.txt", "w"), File("stderr.txt", "w"));
			if (proc.processID < 1) {
				return false;
            }
			//MessageBoxW(null, "Zapret запущен\0"w.ptr, "\0"w.ptr, 0);
			auto avg = rankConnection(tries, LFLAGS.keepConsole, progressTick);
			if (avg < 0) {
				// Ошибка
				return false;
			}
			writefln("Test resulted in avg %d", avg);
			if (avg < time) {
				time = avg;
				key = j;
			}
			kill(proc);
			stdout.flush();
		}
		auto resultCommand = baseCommand ~ fixed ~ split(variants[key], " ");
		writefln("Best result of %d from '%s'", time, resultCommand);
        foreach (part; resultCommand) {
            if (indexOf(part, toolpath) > 0) {
                replace(part, toolpath, "%DIR%");
            }
        }
		// Обновим команду запуска, исключив путь до исполняемого файла
		zapretDefaultCommand = resultCommand[1..$];
		ConfigManager.setZapretCommand = resultCommand[1..$];
	}

	return true;
}

// Потом это надо разбить на проверку обновлений и скачивание
bool downloadGoodbyeDPI(uint repeats = 0) {
	try {
		//string responseCache = getReleasesJSON(TOOLS["GoodbyeDPI"w]);
        string responseCache = getReleasesJSONCurl(TOOLS["GoodbyeDPI"w]);
		if (responseCache.length < 1) {
			return false;
        }

		import std.json;
		import std.file;
		auto responseJSON = parseJSON(responseCache);
		if (responseJSON.type() != JSONType.array) {
			// Получили какое-то фуфло, но тем не менее JSON правильный
			writefln("(%d) GitHub API returned crap for '%s'", repeats, TOOLS["Zapret"w]);
			downloadGoodbyeDPI(repeats + 1);
			if (repeats < 5) {
				// Какой-то	из вызовов завершился успехом
				return true;
            }
			// Пойдём дальше, чтобы нарваться на Exception
        }
		
		auto latest = responseJSON[0];
		//writeln(json[0]["zipball_url"]);
		auto ver = latest["name"].get!string;
		//auto publishedAt = latest["published_at"];
		wstring zipUrl = ""w;
		foreach	(entry; latest["assets"].array) {
			string n = entry["name"].get!string;
			// Там были перепаковки с -2, надо учитывать их
			if (
				n[0..11+ver.length] == "goodbyedpi-" ~ ver
				&& n[$-4..$] == ".zip"
			) {
				// Предполагаем что это архив с релизом
				zipUrl = to!wstring(entry["browser_download_url"].get!string);
            }
        }
		//to!wstring(latest["assets"][0]["browser_download_url"].get!string);

		// Немного проверок на адекватность
		if (exists("tools\\goodbyedpi") && !isDir("tools\\goodbyedpi")) {
			remove("tools\\goodbyedpi");
        }
		if (!exists("tools\\goodbyedpi")) {
			mkdirRecurse("tools\\goodbyedpi");
        }
		if (!exists("tools\\goodbyedpi\\" ~ ver) && !exists("tools\\goodbyedpi\\inst")) {
			writeln("Installing GoodbyeDPI " ~ ver);
			auto oldPath = dirEntries(".\\tools\\goodbyedpi", SpanMode.shallow).front.name;
			downloadAndExtract(zipUrl, ".\\tools\\goodbyedpi", ver);
			remove("tools\\goodbyedpi\\" ~ ver ~ ".zip");

			// Запишем здесь маску какие файлы нам нужны, чтобы не распаковывать весь архив целиком
			string[] filesToExtract = [
				"goodbyedpi.exe",
				"WinDivert64.sys",
				"WinDivert.dll"
			];
			
			// Подразумеваем что всё ок
			mkdir(".\\tools\\goodbyedpi\\" ~ ver);
			auto verdirname = dirEntries(".\\tools\\goodbyedpi\\inst", SpanMode.shallow).front.name;
			// Подразумеваем что я не забыл проверить что этот путь всё ещё актуален
			foreach (f; filesToExtract) {
				// Я гнида, так что поддерживается только x64
				rename(verdirname ~ "\\x86_64\\" ~ f, "tools\\goodbyedpi\\" ~ ver ~ "\\" ~ f);
            }
			// Удалим остатки и старую версию (если была)
			rmdirRecurse(".\\tools\\goodbyedpi\\inst");
			if (oldPath.length > 0) {
				rmdirRecurse(oldPath);
			}
			return true;
        }
	} catch (Throwable ex) {
		// По какой-то причине, если делать запросы циклом, на 17-й раз в responseCache всё кривое
		printFormattedException(ex);
		return false;
	}

	return true;
}

bool downloadZapret(uint repeats = 0) {
	try {
		//string responseCache = getReleasesJSON(TOOLS["Zapret"w]);
		string responseCache = getReleasesJSONCurl(TOOLS["Zapret"w]);
		if (responseCache.length < 1) {
			return false;
        }

		import std.json;
		import std.file;
		auto responseJSON = parseJSON(responseCache);
		if (responseJSON.type() != JSONType.array) {
			// Получили какое-то фуфло, но тем не менее JSON правильный
			writefln("(%d) GitHub API returned crap for '%s'", repeats, TOOLS["Zapret"w]);
			downloadZapret(repeats + 1);
			if (repeats < 5) {
				// Какой-то	из вызовов завершился успехом
				return true;
            }
			// Пойдём дальше, чтобы нарваться на Exception
        }

		auto latest = responseJSON[0];
		//writeln(json[0]["zipball_url"]);
		auto ver = latest["name"].get!string;
		//auto publishedAt = latest["published_at"];
		wstring zipUrl = ""w;
		foreach	(entry; latest["assets"].array) {
			string n = entry["name"].get!string;
			// Довольно фиговая идея так делать, но пока работает - пускай работает
			if (n == "zapret-" ~ ver ~ ".zip") {
				zipUrl = to!wstring(entry["browser_download_url"].get!string);
            }
        }
		//auto zipUrl = to!wstring(latest["assets"][0]["browser_download_url"].get!string);

		// Тут тоже немного проверок на адекватность
		if (exists("tools\\zapret") && !isDir("tools\\zapret")) {
			remove("tools\\zapret");
        }
		if (!exists("tools\\zapret")) {
			mkdirRecurse("tools\\zapret");
        }
		if (!exists("tools\\zapret\\" ~ ver) && !exists("tools\\zapret\\inst")) {
			writeln("Installing Zapret " ~ ver);
			auto oldPath = dirEntries(".\\tools\\zapret", SpanMode.shallow).front.name;
			downloadAndExtract(zipUrl, ".\\tools\\zapret", ver);
			remove("tools\\zapret\\" ~ ver ~ ".zip");
            
			// Запишем здесь маску какие файлы нам нужны, чтобы не распаковывать весь архив целиком
			string[] binsToExtract = [
				"winws.exe",
				"WinDivert64.sys",
				"WinDivert.dll",
				"cygwin1.dll",
				// Вот эти не уверен что прям нужны, но пусть будут для полноты
				"ip2net.exe",
				"killall.exe",
				"mdig.exe"
			];
			string[] fakesToExtract = [
				// Пока пользуемся только двумя, значит берём их и всё
				"quic_initial_www_google_com.bin",
				"tls_clienthello_www_google_com.bin"
			];
			string[] optionalFakes = [
				// Эти извлекаем если есть, потом надо динамически достраивать список фейков для автонастройки
				"quic_initial_vk_com.bin",
				"tls_clienthello_gosuslugi_ru.bin",
				"tls_clienthello_sberbank_ru.bin",
				"tls_clienthello_vk_com.bin",
				"tls_clienthello_vk_com_kyber.bin"
			];
			
			// Подразумеваем что всё ок
			mkdir(".\\tools\\zapret\\" ~ ver);
			auto verdirname = dirEntries(".\\tools\\zapret\\inst", SpanMode.shallow).front.name;
			// Подразумеваем что я не забыл проверить что этот путь всё ещё актуален
            if (exists(verdirname ~ "\\binaries\\win64") && isDir(verdirname ~ "\\binaries\\win64")) {
                writefln("dir %s exists", verdirname ~ "\\binaries\\win64");
                foreach (f; binsToExtract) {
                    rename(verdirname ~ "\\binaries\\win64\\" ~ f, "tools\\zapret\\" ~ ver ~ "\\" ~ f);
                }
            } else if (exists(verdirname ~ "\\binaries\\windows-x86_64\\") && isDir(verdirname ~ "\\binaries\\windows-x86_64\\")) {
                writefln("dir %s exists", verdirname ~ "\\binaries\\windows-x86_64\\");
                foreach (f; binsToExtract) {
                    rename(verdirname ~ "\\binaries\\windows-x86_64\\" ~ f, "tools\\zapret\\" ~ ver ~ "\\" ~ f);
                }
            } else {
                throw new Exception("Windows binaries location changed!");
            }
			foreach (f; fakesToExtract) {
				rename(verdirname ~ "\\files\\fake\\" ~ f, "tools\\zapret\\" ~ ver ~ "\\" ~ f);
            }
			foreach (f; optionalFakes) {
                if (exists(verdirname ~ "\\files\\fake\\" ~ f)) {
                    rename(verdirname ~ "\\files\\fake\\" ~ f, "tools\\zapret\\" ~ ver ~ "\\" ~ f);
                }
            }
			// Удалим остатки и старую версию (если была)
			rmdirRecurse(".\\tools\\zapret\\inst");
			if (oldPath.length > 0) {
				rmdirRecurse(oldPath);
			}
			return true;
        }
	} catch (Throwable ex) {
		// По какой-то причине, если делать запросы циклом, на 17-й раз в responseCache всё кривое
		printFormattedException(ex);
		return false;
	}

	return true;
}