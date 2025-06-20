module network;

import std.conv : to;
import std.file;
import std.stdio : writefln, writeln;
import std.string;
import std.typecons;

import core.time;

import core.sys.windows.winbase;
import core.sys.windows.wininet;
import core.sys.windows.winnt;

static import curl = std.net.curl;

import utils;

alias CurlResult = Tuple!(ushort, "code", string, "data");

// TODO : Сделать изменяемыми из раздела продвинутых настроек
// Пока репозиторий приватный использую тестовую ссылку
const wstring verURL = "https://raw.githubusercontent.com/DeenOConnor/verbose-octo-goggles/refs/heads/master/ver"w;
//const wstring verURL = "https://raw.githubusercontent.com/DeenOConnor/DieDPI/refs/heads/master/ver\0"w;
const wstring relURL = "https://api.github.com/repos/DeenOConnor/verbose-octo-goggles/releases"w;
//const wstring relURL = "https://api.github.com/repos/DeenOConnor/DieDPI/releases"w;

// Не совсем круто зашивать проверочные сайты, но так выходит удобнее
// Пользователю нужно давать возможность редактировать и сохранять свой список
// Ещё есть сомнения что список оптимальный, т.к. есть провайдеры, у которых почти всё из него и так работает
// Составлять нужно, конечно, по потребностям пользователей, но надо иметь и небольшой универсальный по умолчанию
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

// Незачем пересоздавать каждый раз
const(wchar)*[] accept;
wstring apiHeaders;
wstring dlHeaders;
wstring updHeaders;
HINTERNET internet;
// Надо будет посмотреть, может быть имеет смысл прикидываться браузером или вообще рандомизировать
wstring useragent = "DieDPI-v0.0.0-WinINet\0"w;
string useragentCurl = "DieDPI-v0.0.0-libcurl\0";

import dbg : debugAuth = dbgAuthHeader;

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
	
	apiHeaders = 
"Accept: text/html,application/xhtml+xml,application/xml,application/json
Accept-Charset: utf-8
Host: api.github.com"w ~ debugAuth;
	dlHeaders = 
"Accept: text/html,application/xhtml+xml,application/xml,application/json
Accept-Charset: utf-8
Host: github.com"w;
	updHeaders = 
"Accept: text/html,application/xhtml+xml,application/xml,application/json
Accept-Charset: utf-8
Host: raw.githubusercontent.com"w;

	internet = InternetOpenW(useragent.ptr, INTERNET_OPEN_TYPE_DIRECT, null, null, 0);
	if (internet is null) {
		writefln("InternetOpenW failed: 0x%08X", GetLastError());
		return false;
	}
	
	return true;
}

void closeInternet() {
	if (internet !is null) {
		InternetCloseHandle(internet);
    }
}

void* openPage(wstring url, wstring headers) {
	auto req = InternetOpenUrlW(
		internet,
		url.dup.ptr,
		headers.dup.ptr,
		to!uint(headers.length),
		INTERNET_FLAG_IGNORE_REDIRECT_TO_HTTP | INTERNET_FLAG_IGNORE_REDIRECT_TO_HTTPS | INTERNET_FLAG_NO_CACHE_WRITE,
		0
	);
	if (req is null) {
		writefln("InternetOpenUrlW for %s failed: 0x%08X", url, GetLastError());
		uint err, bufLen;
		wchar[1] buf;
		auto r = InternetGetLastResponseInfoW(&err, buf.ptr, &bufLen);
		if (!r && GetLastError() == 0x7A) {
			buf = new wchar[bufLen];
			InternetGetLastResponseInfoW(&err, buf.ptr, &bufLen);
		}
		writefln("Last response: %s", buf);
	}
	
	// Вызывающему нужно следить за закрытием дескриптора
	return req;
}


CurlResult curlOpenPage(string url, uint timeout = 15) {
    auto headers = ["User-Agent": useragentCurl];
    return curlOpenPage(url, headers, timeout);
}

CurlResult curlOpenPage(string url, string[string] headers, uint timeout = 15) {
    CurlResult res;
    
    try {
        writefln("Attempting to open \"%s\"", url);
        if ("User-Agent" !in headers) {
            headers["User-Agent"] = useragentCurl;
        }
        auto http = curl.HTTP(url);
        foreach (k, v; headers) {
            http.addRequestHeader(k, v);
        }
        http.method(http.Method.get);
        http.connectTimeout(dur!"seconds"(timeout));
        string result = "";
        http.onReceive = delegate size_t(ubyte[] data) {
            import std.algorithm.comparison;
            result = to!string(data[0 .. min(data.length, 10)]);
            return data.length;
        };
        http.perform();
        res.code = http.statusLine.code;
        res.data = result;
    } catch (Exception ex) {
        printFormattedException(ex);
        
        res.code = 999;
        res.data = "";
    }
    return res;
}

string getReleasesJSONCurl(wstring url) {
    return getReleasesJSONCurl(to!string(url));
}

string getReleasesJSONCurl(string url) {
    writefln("Requested releases JSON from %s", url);
    return curl.get(url).idup;
}

void downloadAndExtractCurl(string url, string path, string name) {
    writefln("Requested download and extract %s to %s from %s", name, path, url);
    if (!exists(path ~ "\\" ~ name ~ ".zip")) {
		if (!exists(path)) {
			// Создадим папку, если такой ещё нет
			mkdirRecurse(path);
		}
        curl.download(url, path ~ "\\" ~ name ~ ".zip");
    } else {
		writeln("File exists");
    }
	import utils;
	extractZip(path ~ "\\" ~ name ~ ".zip", path ~ "\\inst");
}

string getReleasesJSON(wstring url) {
	writefln("Fetching releases from '%s'", url);

	auto req = openPage(url, apiHeaders);
	if (req is null) {
		return "{}";
	}
	scope(exit) InternetCloseHandle(req);

	char[] responseBuffer = new char[1024];
	char[] responseCache;
	// Если запрашивать список всех релизов, то нулевой будет самым последним, даже если это не полный релиз
	int responseResult = 1;
	uint bytenum = 1;
	ulong actualRead = 0;

	do {
		responseResult = InternetReadFile(req, responseBuffer.ptr, 1024, &bytenum);
		actualRead += bytenum;
		// По какой-то причине ответ иногда испорчен, и всегда по-разному
		responseBuffer.length = bytenum;
		auto badData = indexOf(responseBuffer, "\n");
		if (badData >= 0) {
			responseBuffer = responseBuffer[0..badData];
			// Заканчиваем
			responseResult = -1;
			bytenum = 0;
        }
		responseCache ~= responseBuffer.dup;
		auto bd = 1;
	} while (responseResult == 0 || bytenum != 0);

	if (!responseResult) {
		auto err = GetLastError();
		if (err == 0x7A) {
			writefln("InternetReadFile wants a bigger buffer: %d", bytenum);
		} else {
			writefln("InternetReadFile failed: 0x%08X", GetLastError());
		}
		return "{}";
	}

	return to!string(responseCache);
}

void downloadAndExtract(wstring url, string path, string name) {
	import std.file;
	import std.stdio;

	// Проверим надо ли качать файл
	if (!exists(path ~ "\\" ~ name ~ ".zip")) {
		if (!exists(path)) {
			// Создадим папку, если такой ещё нет
			mkdirRecurse(path);
		}

		auto req = openPage(url, dlHeaders);
		if (req is null) {
			// Плохая ситуация
			return;
        }
		scope(exit) InternetCloseHandle(req);

		ubyte[] responseBuffer = new ubyte[1024];

		File downloadLoc = File(path ~ "\\" ~ name ~ ".zip", "w");
		int responseResult = 1;
		uint bytenum = 1;
		ulong actualRead = 0;

		do {
			responseResult = InternetReadFile(req, responseBuffer.ptr, 1024, &bytenum);
			if (bytenum != 0) {
				actualRead += bytenum;
				responseBuffer.length = bytenum;
				downloadLoc.rawWrite(responseBuffer);
			}
		} while (responseResult == 0 || bytenum != 0);
	} else {
		writeln("File already exists");
    }
	// Предполагаем что на данный момент файла не может не быть
	import utils;
	extractZip(path ~ "\\" ~ name ~ ".zip", path ~ "\\inst");
}


long rankConnection(uint tries, bool dbg = false, void function() progressTick = { return; }) {
	import std.algorithm.iteration : fold;
	import std.stdio : stdout;

	long[] totals = new long[tries];
	long[long][] details = new long[long][testURLs.length];

	foreach (i; 0..tries) {
		if (dbg) {
			writefln("Rank connections attempt #%d", i);
        }
		foreach (j, url; testURLs) {
			if (dbg) {
				writefln("Testing %s", url);
			}
			auto t = timeConnection(url, internet, accept);
			if (t < -1) {
				// Есть проблема
				return t;
            }
			if (t == -1) {
				// Примем ошибку соединения за 15 секунд, т.к. нас либо футболит DPI, либо фильтр по IP
				// Ну а если уж у пользователя реально такая задержка, то у него есть проблемы посерьёзнее
				t = 150000000;
			}
			
			totals[i] += t;
			details[j][i] = t;
			stdout.flush();
			progressTick(); // Ткнём следящего что есть прогресс
		}
		if (dbg) {
			writeln();
        }
	}

	if (dbg) {
		import std.stdio: writef;
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
		return -2;
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
		return -3;
	}

	auto queryRequest = HttpSendRequestW(req, null, -1, null, 0);
	if (!queryRequest) {
		writefln("HttpSendRequestW failed: 0x%08X", GetLastError());
		return -1;
	}

	auto queryResult = HttpQueryInfoW(req, /*HTTP_QUERY_CONTENT_LENGTH*/ HTTP_QUERY_STATUS_CODE, &buf, &bufLen, &headerNum);

	if (!QueryPerformanceCounter(&end)) {
		writefln("QueryPerformanceCounter failed: 0x%08X", GetLastError());
		return -4;
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