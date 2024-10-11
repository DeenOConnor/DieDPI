import std.stdio;
import std.conv;

import core.sys.windows.winbase;
import core.sys.windows.wininet;
import core.sys.windows.winnt;

import core.sys.windows.wincon : FreeConsole;
import core.sys.windows.winuser : MessageBoxW, MB_ICONERROR;

pragma(lib, "advapi32");
pragma(lib, "user32");
pragma(lib, "wininet");
// pragma(lib, "kernel32"); ?

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

void main()
{
	if (!isRunningAsAdmin()) {
		writeln("false");
		MessageBoxW(null, "Программа должна быть запущена с правами администратора!\0"w.ptr, "Ошибка!\0"w.ptr, MB_ICONERROR);
		return;
	}
	
	wstring mname = "DieDPI_Default_Mutex\0"w;
	auto mres = CreateMutexW(null, TRUE, mname.ptr);
	if (mres is null || GetLastError() == ERROR_ALREADY_EXISTS) {
		MessageBoxW(null, "Не может быть запущено больше одного экземпляра программы!\0"w.ptr, "Ошибка!\0"w.ptr, MB_ICONERROR);
		return;
	}
	
	if (!configureInternet()) {
		MessageBoxW(null, "Не удалось настроить соединение с интернетом!\0"w.ptr, "Ошибка!\0"w.ptr, MB_ICONERROR);
		return;
	}
	scope(exit) InternetCloseHandle(internet);
	
	// Когда будет запускаться через DFL, надо перед появлением окна прибивать консольку
	//FreeConsole();
	try {
		//auto time = rankConnection(true);
		//writefln("Average response time: %d microseconds", time);
		writeln(autosetupGoodbyeDPI());
	} catch (Throwable ex) {
		writefln("%s\n%s:%d", ex.msg, ex.file, ex.line);
	}
	
	readln();
}

// Пока что всё пихаем в один файл, а дальше разберёмся как это организовать
uint ver = 0;

// Незачем пересоздавать каждый раз
const(wchar)*[] accept;
HINTERNET internet;
wstring useragent = "DieDPI-v0.0.0-WinInet\0"w;

// Это лучше заполнять из какого-нибудь конфига
const auto TOOLS = [
	"GoodbyeDPI"w: "https://api.github.com/repos/ValdikSS/GoodbyeDPI/releases\0"w,
	"ByeDPI"w: "https://api.github.com/repos/hufrea/byedpi/releases\0"w,
	// Ещё надо добавить настройку через zapret
];

wstring[] testURLs = [
	"deviantart.com\0"w,
	"discord.com\0"w,
	"e621.net\0"w,
	"facebook.com\0"w,
	"ficbook.net\0"w,
	"furaffinity.net\0"w,
	"instagram.com\0"w,
	"meta.com\0"w,
	"patreon.com\0"w,
	"pornhub.com\0"w,
	"rutor.org\0"w,
	"rutracker.org\0"w,
	"twitter.com\0"w,
	"youtu.be\0"w,
	"wixmp.com\0"w,
];

// Надо придумать как по-нормальному это сделать
wstring accept1 = "text/html\0"w;
wstring accept2 = "application/xhtml+xml\0"w;
wstring accept3 = "application/xml\0"w;

bool configureInternet() {
	// Заполняем здесь, т.к. нам нужны указатели на строки для HttpOpenRequestW
	accept = [
		accept1.dup.ptr,
		accept2.dup.ptr,
		accept3.dup.ptr,
		null
	];

	internet = InternetOpenW(useragent.ptr, INTERNET_OPEN_TYPE_DIRECT, null, null, 0);
	if (internet is null) {
		writefln("InternetOpenW failed: 0x%08X", GetLastError());
		readln();
		return false;
	}
	
	return true;
}

long rankConnection(bool dbg = false) {
	import std.algorithm.iteration : fold;

	long[5] totals;
	long[long][15] details;

	foreach (i; 0..5) {
		foreach (j, url; testURLs) {
			auto t = timeConnection(url, internet, accept);
			if (t == -1) {
				// Примем ошибку соединения за 5 секунд, т.к. нас либо футболит DPI, либо фильтр по IP
				t = 50000000;
			}
			
			totals[i] += t;
			details[j][i] = t;
			stdout.flush();
		}
		writeln();
	}

	if (dbg) {
		foreach (index, times; details) {
			writef("Calculated response times for %s as ", testURLs[index]);
			long tot = 0;
			foreach (time; times) {
				writef("%d, ", time);
				tot += time;
			}
			writefln("avg %d", tot/5);
		}
	}

	//writefln("Calculated total response time: %d microseconds", total);
	//return totals.fold!((a, b) => a + b);
	long t = 0;
	foreach (i; totals) {
		t += i/5;
	}
	return t/5;
}

long timeConnection(wstring url, HINTERNET internet, const(wchar)*[] accept) {
	auto inet = InternetConnectW(
		internet,
		url.dup.ptr,
		INTERNET_DEFAULT_HTTPS_PORT,
		null,
		null,
		INTERNET_SERVICE_HTTP,
		INTERNET_FLAG_DONT_CACHE,
		10L
	);
	scope(exit) InternetCloseHandle(inet);
	if (inet is null) {
		writefln("InternetConnectW for %s failed: 0x%08X", url, GetLastError());
		return -1;
	}

	auto req = HttpOpenRequestW(
		inet,
		null,
		"/\0"w.ptr,
		null,
		null,
		accept.ptr,
		INTERNET_FLAG_IGNORE_REDIRECT_TO_HTTPS | INTERNET_FLAG_PRAGMA_NOCACHE | INTERNET_FLAG_SECURE,
		10L
	);
	scope(exit) InternetCloseHandle(req);

	if (req is null) {
		writefln("Couldn't connect to %s: 0x%08X", url, GetLastError());
		return -1;
	}

	ulong buf;
	uint headerNum = 0, bufLen = 1 * ulong.sizeof;

	//writefln("Connecting to %s", url);
	LARGE_INTEGER start, end;
	if (!QueryPerformanceCounter(&start)) {
		writefln("QueryPerformanceCounter failed: 0x%08X", GetLastError());
		return -1;
	}

	auto queryRequest = HttpSendRequestW(req, null, -1, null, 0);
	if (!queryRequest) {
		writefln("HttpSendRequestW failed: 0x%08X", GetLastError());
		return -1;
	}

	auto queryResult = HttpQueryInfoW(req, /*HTTP_QUERY_CONTENT_LENGTH*/ HTTP_QUERY_STATUS_CODE, &buf, &bufLen, &headerNum);

	if (!QueryPerformanceCounter(&end)) {
		writefln("QueryPerformanceCounter failed: 0x%08X", GetLastError());
		return -1;
	}

	if (!queryResult) {
		auto err = GetLastError();
		if (err == 0x7A) {
			writefln("HttpQueryInfoW wants a bigger buffer: %d", bufLen);
		} else {
			writefln("HttpQueryInfoW failed: 0x%08X", GetLastError());
		}
		return -1;
	}

	// uint resp;
	// foreach (index, k; buf) {
		// if (k != 0) {
			// resp += k;
			// writef("%d:%d ", index, k);
		// }
	// }

	//writefln("%s responde with code %d in %d microseconds", url, buf, (end.QuadPart - start.QuadPart));
	//writefln("%d:%s", i, url);
	//details[j][i] = end.QuadPart - start.QuadPart;
	//totals[i] += end.QuadPart - start.QuadPart;
	return end.QuadPart - start.QuadPart;
}

// По идее GoodbyeDPI - это стандатный вариант
bool autosetupGoodbyeDPI() {
	import std.array;
	import std.file;
	import std.string;
	import std.process;

	if (
		!exists("goodbyedpi.exe")
		|| isDir("goodbyedpi.exe")
	) {
		return false;
	}
	
	auto command = [
		"goodbyedpi.exe",
		"-5",
		"--dns-addr", "77.88.8.8",
		"--dns-port", "1253",
		"--dnsv6-addr", "2a02:6b8::feed:0ff",
		"--dnsv6-port", "1253",
		"--blacklist", "..\\russia-blacklist.txt",
		"--blacklist", "..\\russia-youtube.txt"
	];

	long time = long.max;
	int key;
	foreach (int i; 5..10) {
		command[1] = "-" ~ text(i);
		auto proc = spawnProcess(command, File("stdin.txt", "r"), File("stdout.txt", "w"), File("stderr.txt", "w"));
		//MessageBoxW(null, "GoodbyeDPI запущен\0"w.ptr, "\0"w.ptr, 0);
		auto avg = rankConnection(true);
		writefln("Trying GoodbyeDPI with -%d resulted in avg %d", i, avg);
		if (avg < time) {
			time = avg;
			key = i;
		}
		kill(proc);
		stdout.flush();
	}
	writefln("Best response time %d with key -%d", time, key);
	return true;
}

bool autosetupByeDPI() {
	return false;
}