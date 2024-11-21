module WindowsApp1;

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
		//writeln("false");
		//MessageBoxW(null, "Программа должна быть запущена с правами администратора!\0"w.ptr, "Ошибка!\0"w.ptr, MB_ICONERROR);
		//return;
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
		//writeln(autosetupGoodbyeDPI());
		//writeln(autosetupZapret());
		foreach (i; 0..100) {
			writeln(downloadGoodbyeDPI());
		}
	} catch (Throwable ex) {
		writefln("%s\n%s:%d", ex.msg, ex.file, ex.line);
	}
	
	cast(void) readln();
}


// Пока что всё пихаем в один файл, а дальше разберёмся как это организовать


const uint ver = 0;
const wstring verURL = "https://raw.githubusercontent.com/DeenOConnor/DieDPI/refs/heads/master/ver\0"w;
const wstring relURL = "https://api.github.com/repos/ValdikSS/GoodbyeDPI/releases\0"w;

// Незачем пересоздавать каждый раз
const(wchar)*[] accept;
HINTERNET internet;
// Надо будет посмотреть, может быть имеет смысл прикидываться браузером или вообще рандомизировать
wstring useragent = "DieDPI-v0.0.0-WinINet\0"w;

// Это лучше заполнять из какого-нибудь конфига
// А ещё это нихера блин не работает
const auto TOOLS = [
	// Один из последних релизов GoodbyeDPI помечен как пре-релиз, и поэтому по ссылке на latest открывается устаревший
	"GoodbyeDPI"w: "https://api.github.com/repos/ValdikSS/GoodbyeDPI/releases\0"w,
	// Т.к. это уже готовые билды, нам пофиг на версию, обновлять можно сверяя время изменения файла
	"Zapret"w: "https://github.com/bol-van/zapret-win-bundle/archive/refs/heads/master.zip\0"w,
	// Надо подумать актуально ли ByeDPI
	// Потенциально тем, у кого общий комп, и не получится гонять софт от админа
	// Тогда встаёт вопрос как в автоматическом режиме задавать прокси при включении обхода
	// Вроде можно через InternetSetOption, задавая значение PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY
	// "ByeDPI"w: "https://api.github.com/repos/hufrea/byedpi/releases\0"w,
];

// Не совсем круто зашивать проверочные сайты, но так выходит удобнее
// Пользователю нужно давать возможность редактировать и сохранять свой список
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
	// Вообще надо выяснить какие адреса использует дискорд для RTC, и проверять также парочку их них
	// Но пока GoodbyeDPI не научится работать с UDP, это по большому счёту его отметёт как вариант обхода
];

// Надо придумать как по-нормальному это сделать
wstring accept1 = "text/html\0"w;
wstring accept2 = "application/xhtml+xml\0"w;
wstring accept3 = "application/xml\0"w;
wstring accept4 = "application/json\0"w;

bool configureInternet() {
	// Заполняем здесь, т.к. для HttpOpenRequestW нужны указатели на строки 
	accept = [
		accept1.dup.ptr,
		accept2.dup.ptr,
		accept3.dup.ptr,
		accept4.dup.ptr,
		null
	];

	internet = InternetOpenW(useragent.ptr, INTERNET_OPEN_TYPE_DIRECT, null, null, 0);
	if (internet is null) {
		writefln("InternetOpenW failed: 0x%08X", GetLastError());
		cast(void) readln();
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
				// Ну а если уж у пользователя реально такая задержка, то у него есть проблемы посерьёзнее
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

// По идее GoodbyeDPI - это должен быть "стандатный" вариант, особенно когда он наконец научится работать с UDP
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
		// Сайты банятся как попало, в т.ч. без постановления и внесения в реестр, так что не вижу смысла вести списки 
		// "--blacklist", "..\\russia-blacklist.txt",
		// "--blacklist", "..\\russia-youtube.txt"
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

bool autosetupZapret() {
	import std.array;
	import std.file;
	import std.process;

	// Проверим что все нужные zapret-у файлы на месте
	if (
		!exists("winws.exe")
		|| isDir("winws.exe")
		|| !exists("WinDivert64.sys")
		|| isDir("WinDivert64.sys")
		|| !exists("WinDivert.dll")
		|| isDir("WinDivert.dll")
		|| !exists("cygwin1.dll")
		|| isDir("cygwin1.dll")
		|| !exists("quic_initial_www_google_com.bin")
		|| isDir("quic_initial_www_google_com.bin")
		|| !exists("tls_clienthello_www_google_com.bin")
		|| isDir("tls_clienthello_www_google_com.bin")
	) {
		return false;
	}

	// Тут не смотрим на 80 порт, но я не уверен что у всех провайдеров можно на него забить
	// Пока что, вроде, все, у кого проверяли, разницы не ощутили
	auto baseCommand = [
		"winws.exe",
		"--wf-tcp=443", // "--wf-tcp=80,443",
		"--wf-udp=443,50000-65535", // "--wf-udp=80,443,50000-65535",
		"--dpi-desync-repeats=3",
		"--dpi-desync-udplen-increment=12",
		"--dpi-desync-udplen-pattern=0xF00F",
		"--dpi-desync-fake-quic=quic_initial_www_google_com.bin",
		"--dpi-desync-any-protocol",
		"--dpi-desync-autottl=2",
		//"--dpi-desync-fake-tls=\"tls_clienthello_www_google_com.bin\"",
		// Надо попробовать вычислять количество узлов провайдера через tracert и указывать TTL так
		// "--dpi-desync-ttl=4"
	];

	// Войс не работает, если убрать --dpi-desync-fooling=badseq, --dpi-desync-any-protocol, --dpi-desync-cutoff=d3 или fake-quic и fake-tls
	// Вообще эта штука должна работать +- для всех
	auto discordCommand = split("winws.exe --wf-tcp=443 --wf-udp=443,50000-65535 --dpi-desync=fake,split --dpi-desync-repeats=3 --dpi-desync-fooling=badseq --dpi-desync-udplen-increment=12 --dpi-desync-udplen-pattern=0xF00F --dpi-desync-fake-quic=\"quic_initial_www_google_com.bin\" --dpi-desync-any-protocol --dpi-desync-cutoff=d3 --dpi-desync-autottl=2 --dpi-desync-fake-tls=\"tls_clienthello_www_google_com.bin\"", " ");

	// Т.к. у zapret-winws нереально много параметров, будем пробовать перебирать режимами
	auto modes = [
		1: [
			"--dpi-desync=": ["fake,split"], // По-моему не получится сюда приткнуть disorder, хотя он работает неплохо
			"--dpi-desync-fooling=": ["badseq", "md5sig"], // Дискорд лучше всего себя чувствует с badseq, но md5sig тоже помогает
			"--dpi-desync-cutoff=": ["d3"], // Я уже не помню почему именно 2 и 3
			"--dpi-desync-fake-tls=" : ["", "tls_clienthello_www_google_com.bin"] // На МТС поддельный clienthello всё только портит
		],
		2: [
			// Потом погоняю, дополню
			"": [""]
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
			//MessageBoxW(null, "Zapret запущен\0"w.ptr, "\0"w.ptr, 0);
			auto avg = rankConnection(true);
			writefln("Test resulted in avg %d", avg);
			if (avg < time) {
				time = avg;
				key = j;
			}
			kill(proc);
			stdout.flush();
		}
		writefln("Best result of %d from '%s'", time, baseCommand ~ fixed ~ split(variants[key], " "));
	}

	return true;
}

bool downloadGoodbyeDPI() {
	import std.string;
	
	// Почему-то просто HTTP... варианта нет, но они оба 51, так что норм
	import core.sys.windows.winhttp : HTTP_QUERY_CONTENT_LOCATION = WINHTTP_QUERY_CONTENT_LOCATION;

	auto url = TOOLS["GoodbyeDPI"w];
	auto headers = 
"Accept: text/html,application/xhtml+xml,application/xml,application/json
Accept-Charset: utf-8
Host: api.github.com"w;

	auto req = InternetOpenUrlW(
		internet,
		url.dup.ptr,
		headers.ptr,
		to!uint(headers.length),
		INTERNET_FLAG_IGNORE_REDIRECT_TO_HTTP | INTERNET_FLAG_IGNORE_REDIRECT_TO_HTTPS | INTERNET_FLAG_NO_CACHE_WRITE,
		0
	);
	scope(exit) InternetCloseHandle(req);
	if (req is null) {
		writefln("InternetOpenUrlW for %s failed: 0x%08X", url, GetLastError());
		return false;
	}

	char[] responseBuffer = new char[1024];
	string responseCache = "";
	// Если запрашивать список всех релизов, то нулевой будет самым последним, даже если это не полный релиз
	int responseResult = 1;
	uint bytenum = 1;
	ulong actualRead = 0;

	do {
		responseResult = InternetReadFile(req, responseBuffer.ptr, 1024, &bytenum);
		actualRead += bytenum;
		// Не знаю какое колдовство там происходит, но в определённый момент начинают читаться заново уже прочитанные куски ответа
		auto badData = indexOf(responseBuffer, "\n");
		if (badData >= 0) {
			responseBuffer = responseBuffer[0..badData];
			// Заканчиваем
			responseResult = -1;
			bytenum = 0;
        }
		responseCache ~= fromStringz(responseBuffer.ptr);
	} while (responseResult == 0 || bytenum != 0);
	//writefln("InternetReadFile finished, read %d bytes", actualRead);

	//writefln("Read response:\n'%s'", responseCache);

	if (!responseResult) {
		auto err = GetLastError();
		if (err == 0x7A) {
			writefln("InternetReadFile wants a bigger buffer: %d", bytenum);
		} else {
			writefln("InternetReadFile failed: 0x%08X", GetLastError());
		}
		return false;
	}

	try {
		import std.json;
		auto json = parseJSON(responseCache);
		writeln(json[0]["zipball_url"]);
	} catch (Throwable ex) {
		writefln("%s\n%s:%d", ex.msg, ex.file, ex.line);
	}

	return true;
}
