module utils;

import std.stdio;

private import cfg;

// Нужно для всяких расширенных выводов в текст боксы и пр. 
private import dfl.control : Control;
Control textBoxOutput;


void printFormattedException(Throwable t, string prefix = "") {
	if (prefix.length > 0 && prefix[$] != '\n') {
		prefix ~= '\n';
    }
	writefln("%s%s\n%s:%d\nTraced from:\n%s", prefix, t.msg, t.file, t.line, t.info);
}

void printUIMessage(wstring str) {
	// Продублируем сообщение в консоль
	writeln(str);
	// TODO : Дописывать строку в конец контрола textBoxOutput
}

void parseArgs(string[] args) {
	/*
		-update: Только самообновление (перенос нужных файлов и чистка старых)
		-kc: Не прибивать окно консоли при запуске
		Параметры ниже не имеют практического смысла без -kc
		-as: Запустить автонастройку и выйти
		-dl: Скачать/обновить инструменты и выйти
		-ud: Проверить собственные обновления и выйти
		-sc: Добавиться в автозапуск и выйти
		-sr: Удалиться из автозапуска и выйти
	*/
	bool s, k, a, d, u, c, r;
	foreach (arg; args) {
		switch (arg) {
			case "-update":
				s = true;
				break;
			case "-kc":
				k = true;
				break;
			case "-as":
				a = true;
				break;
			case "-dl":
				d = true;
				break;
			case "-ud":
				u = true;
				break;
			case "-sc":
				c = true;
				break;
			case "-sd":
				r = true;
				break;
			default:
				break;
        }
    }

	LaunchFlags flags = {
		selfUpdateRun: s,
		keepConsole: k,
		autosetupOnly: a,
		downloadOnly: d,
		updateOnly: u,
		addServiceOnly: c,
		removeServiceOnly: r
    };

	LFLAGS = flags;
}

// Windows
version (Windows) {
	bool isRunningAsAdmin() {
		import core.sys.windows.ntsecapi;

		void* handle = null;
		LSA_OBJECT_ATTRIBUTES loa = {
			0,
			null,
			null,
			0,
			null,
			null
		};
		auto res = LsaNtStatusToWinError(LsaOpenPolicy(null, &loa, 0x10000, &handle));
		if (!res) {
			LsaClose(handle);
			return true;
		}
		return false;
	}
}

string setAutostart(bool toWhat) {
	import std.process;
	import std.file;
	import core.time;
	if (!isRunningAsAdmin()) {
		// Не катит
		return "Нельзя менять состояние автозапуска без прав администратора!";
    }

	auto createFile = File("stdin.txt", "w");
	createFile.close();

	auto command = [
		"schtasks.exe"
	];
	// Соберём команду в зависимости от того, создаём мы или удаляем задание
	command ~= toWhat ? "/create" : "/delete";
	command ~= ["/tn", "diedpi"];
	if (toWhat) {
		command ~= [
			"/tr", thisExePath(),
			"/sc", "ONLOGON",
			"/it",
			"/rl", "highest"
		];
	} else {
		command ~= "/f";
    }
	auto proc = spawnProcess(command, File("stdin.txt", "r"), File("stdout.txt", "w"), File("stderr.txt", "w"));
	// Если уж за две секунды schtasks ничего не сообразил, то и пошёл он в жопу
	proc.waitTimeout(dur!"seconds"(2));

	return "";
}

// TODO : Придумать как извлекать только лишь нужные файлы, а остальное не трогать
void extractZip(string file, string where) {
	import std.file : exists, mkdirRecurse, rmdir, fread = read;
	import std.path : dirName;
	import std.string : indexOf;
	import std.zip;
	// import std.zlib : uncompress;
	import core.memory;

	auto zip = new ZipArchive(fread(file));
	foreach (name, am; zip.directory) {
		if (name[$-1] == '/' || name[$-1] == '\\') {
			// Если это папка, то создадим и перейдём к следующей записи
			mkdirRecurse(where ~ "\\" ~ name);
			continue;
        }
		if (!exists(dirName(where ~ "\\" ~ name))) {
			// Как я понял, в архиве запись о файле в папке может быть раньше записи о папке
			// Поэтому если вдруг мы пытаемся извлечь файл в папку, которой ещё нет, создадим
			mkdirRecurse(dirName(where ~ "\\" ~ name));
        }

		// Если это файл, то распакуем и запишем по нужному пути
		auto data = zip.expand(am);
		// Вызывает ошибку буфера zlib при распаковке некоторых архивов
		// cast(ubyte[]) uncompress(cast(void[]) am.compressedData, am.expandedSize, -15);
		auto f = File(where ~ "\\" ~ name, "w");
		f.rawWrite(data);
		f.flush();
		f.close();
    }
}

