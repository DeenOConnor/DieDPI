module mainform;

import std.conv : to;
import std.stdio : writefln, writeln;

import core.sys.windows.shellapi;
import core.sys.windows.winbase;
import core.sys.windows.windef;
import core.sys.windows.winuser;

import dfl.all;

import cfg;
static import utils;
import settingsform;
import tools : startTool, stopTool;
static import tools;
static import updater;

class MainForm: Form {
	uint iconId = 1001;
	NOTIFYICONDATAW nidw;

	private Config c;

	Bitmap active, inactive;

	PictureBox pictureBox1;
	Button button5;
	Label label6;
	Button button6;
	CheckBox checkBox2;
	ProgressBar progressBar2;
	Button button7;

	SettingsForm settingsForm;

	// Если будет поточиться, то нужно сделать shared
	static bool isRunning = false;

	// Для изменения состояния кнопкой
	private static MainForm instance;
	
	this() {
		import std.file;
		import std.path;
		import std.stdio;
		import core.sys.windows.winbase;
		import core.sys.windows.winuser;

		auto aloc = "tool_active.bmp\0"w;
		auto bmapA = LoadImageW(null, aloc.ptr, IMAGE_BITMAP, 0, 0, LR_CREATEDIBSECTION | LR_LOADFROMFILE);
		if (bmapA is null) {
			auto err = GetLastError();
			writefln("LoadImageW failed: 0x%08X", err);
        } else {
			active = Image.fromHBitmap(bmapA);
        }
		
		auto iloc = "tool_inactive.bmp\0"w;
		auto bmapI = LoadImageW(null, iloc.ptr, IMAGE_BITMAP, 0, 0, LR_CREATEDIBSECTION | LR_LOADFROMFILE);
		if (bmapI is null) {
			auto err = GetLastError();
			writefln("LoadImageW failed: 0x%08X", err);
        } else {
			inactive = Image.fromHBitmap(bmapI);
        }

		initializeMyForm();
		settingsForm = new SettingsForm();
		instance = this;
	}
	
	
	private void initializeMyForm() {
		this.text = "DieDPI v0.1.4";
        debug {
            this.text = this.text ~ "-debug";
        }
		this.clientSize = dfl.all.Size(288, 213);
		this.maximizeBox = false;
		this.formBorderStyle = FormBorderStyle.FIXED_SINGLE;

		pictureBox1 = new dfl.picturebox.PictureBox();
		pictureBox1.name = "pictureBox1";
		pictureBox1.image = inactive;
		pictureBox1.bounds = dfl.all.Rect(8, 48, 128, 128);
		pictureBox1.parent = this;

		button5 = new dfl.button.Button();
		button5.name = "button5";
		button5.text = "Запустить";
		button5.bounds = dfl.all.Rect(144, 48, 131, 23);
		button5.parent = this;

		label6 = new dfl.label.Label();
		label6.name = "label6";
        label6.text = "Work in progress!";
        debug {
            label6.text = "Отладочная версия!";
        }
		label6.textAlign = dfl.all.ContentAlignment.MIDDLE_CENTER;
		label6.bounds = dfl.all.Rect(8, 8, 268, 23);
		label6.parent = this;

		button6 = new dfl.button.Button();
		button6.name = "button6";
		button6.text = "Настроить";
		button6.bounds = dfl.all.Rect(144, 80, 131, 23);
		button6.parent = this;

		checkBox2 = new dfl.button.CheckBox();
		checkBox2.name = "checkBox2";
		checkBox2.text = "Запускать с системой";
		checkBox2.bounds = dfl.all.Rect(144, 144, 131, 23);
		checkBox2.parent = this;

		progressBar2 = new dfl.progressbar.ProgressBar();
		progressBar2.name = "progressBar2";
		progressBar2.bounds = dfl.all.Rect(8, 184, 268, 23);
		progressBar2.parent = this;

		button7 = new dfl.button.Button();
		button7.name = "button7";
		button7.text = "Обновить";
		button7.bounds = dfl.all.Rect(144, 112, 131, 23);
		button7.parent = this;

		void checkBox2_Clicked (Object sender, EventArgs evt) {
            //writeln("Invalidating form");
			string status = utils.setAutostart(checkBox2.checked());
            if (status != "") {
				checkBox2.checked(!checkBox2.checked());
				msgBox(to!wstring(status), "Ошибка!", MsgBoxButtons.OK, MsgBoxIcon.ERROR);
            } else {
				ConfigManager.setAutostart(checkBox2.checked());
            }
        }

		void button5_Clicked (Object sender, EventArgs evt) {
			isRunning = !isRunning;
			auto selectedTool = ConfigManager.getGlobalConfig().tool;
			if (isRunning) {
				isRunning = startTool();
            } else {
				isRunning = !stopTool();
            }
			button5.text(isRunning ? "Остановить"w : "Запустить"w);
			progressBar2.value(100);
			progressBar2.state(isRunning ? ProgressBar.STATE.NORMAL : ProgressBar.STATE.ERROR);

			if (isRunning) {
				pictureBox1.image(active);
            } else {
				pictureBox1.image(inactive);
            }

			if (ConfigManager.getGlobalConfig().autostart) {
				ConfigManager.setPersistentState(isRunning);
			}
		}

		void button6_Clicked (Object sender, EventArgs evt) {
			settingsForm.show();
			settingsForm.bringToFront();
        }

		void button7_Clicked (Object sender, EventArgs evt) {
            button7.text = "Подождите..."w;
            scope(exit) button7.text = "Обновить"w;

            writeln("Checking for updates");
            try {
                //ConfigManager.setUpdateNeeded(true);
                byte updates = 0;
                
                // Разобьём разные обновления, чтобы не ломать все из-за кого-то одного
                try {
                    updates += updater.goodbyeDPIUpdateNeeded() * 1;
                } catch (Exception ex) {
                    utils.printFormattedException(ex);
                    debug {
                        Application.onThreadException(ex);
                    }
                    msgBox("Неожиданная ошибка при получении обновлений GoodbyeDPI"w, "Обновление"w, MsgBoxButtons.OK, MsgBoxIcon.WARNING);
                }
                try {
                    updates += updater.zapretUpdateNeeded() * 2;
                } catch (Exception ex) {
                    utils.printFormattedException(ex);
                    debug {
                        Application.onThreadException(ex);
                    }
                    msgBox("Неожиданная ошибка при получении обновлений Zapret"w, "Обновление"w, MsgBoxButtons.OK, MsgBoxIcon.WARNING);
                }
                try {
                    updates += updater.selfUpdateNeeded() * 4;
                } catch (Exception ex) {
                    utils.printFormattedException(ex);
                    debug {
                        Application.onThreadException(ex);
                    }
                    msgBox("Неожиданная ошибка при получении собственных обновлений"w, "Обновление"w, MsgBoxButtons.OK, MsgBoxIcon.WARNING);
                }

                if (updates == 0) {
                    msgBox("Обновлений не обнаружено"w, "Обновление"w, MsgBoxButtons.OK, MsgBoxIcon.INFORMATION);
                    return;
                }
                
                writefln("Updates found:\nGoodbyeDPI - %s\nZapret - %s\nSelf - %s", !!(updates & 1), !!(updates & 2), !!(updates & 4));
                wstring status;
                if (updates & 1) {
                    if (tools.downloadGoodbyeDPI()) {
                        status ~= "Обновление GoodbyeDPI загружено и установлено\n"w;
                    } else {
                        status ~= "Не удалось обновить GoodbyeDPI"w;
                    }
                }
                if (updates & 2) {
                    if (tools.downloadZapret()) {
                        status ~= "Обновление Zapret загружено и установлено\n"w;
                    } else {
                        status ~= "Не удалось обновить Zapret"w;
                    }
                }
                if (updates & 4) {
                    if (updater.downloadUpdate()) {
                        status ~= "Обновление DieDPI загружено и будет установлено при следующем запуске\n"w;
                    } else {
                        status ~= "Не удалось обновить DieDPI"w;
                    }
                }

                msgBox(status, "Обновление"w, MsgBoxButtons.OK, MsgBoxIcon.INFORMATION);
            } catch (Exception ex) {
                utils.printFormattedException(ex);
                msgBox("Неожиданная ошибка при обновлении"w, "Обновление"w, MsgBoxButtons.OK, MsgBoxIcon.WARNING);
            }
		}

		void mainForm_Loaded (Object sender, EventArgs evt) {
			wchar[128] tip = 0;
			wstring tipText = "Развернуть окно DieDPI\0"w;
			tip[0..tipText.length] = tipText;
			nidw.cbSize = nidw.sizeof;
			nidw.hWnd = this.handle;
			nidw.uID = this.iconId;
			nidw.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_STATE;
			nidw.uCallbackMessage = 0x9090; // Должно быть в пределах 0x8000 .. 0xBFFF
			nidw.szTip = tip;
			nidw.dwState = 0;
			nidw.dwStateMask = NIS_HIDDEN;
			void* icon = LoadIconW(null, IDI_APPLICATION);
			if (icon is null) {
				writefln("Last error 0x%08X", GetLastError());
            }
			nidw.hIcon = icon;
			nidw.uVersion = NOTIFYICON_VERSION;

			Shell_NotifyIconW(NIM_ADD, &nidw);
			writefln("Shell version change: %x", Shell_NotifyIconW(NIM_SETVERSION, &nidw));

			auto globConf = ConfigManager.getGlobalConfig();
			if (globConf.autostart) {
				// Проставим галочку, чтобы пользователь не путался
				checkBox2.checked(true);
				if(globConf.persistentState) {
					// Если мы в автозапуске и последнее состояние было включено - включимся
					button5.performClick();

					// TODO : При автозапуске с включённым инструментом прятать окно?

					return;
                }
			}
			this.focus();
		}

		void mainForm_Closing (Object sender, EventArgs evt) {
			// Если сейчас инструмент запущен - скроемся, а не закроемся
			// Фокус группа пыталась закрыть окно после запуска инструмента
			// и не понимала почему обход не работает, винила программу
			if (isRunning) {
				this.hide();
				if (auto cea = cast(CancelEventArgs) evt) {
					cea.cancel = true;
				}
			} else {
				Shell_NotifyIcon(NIM_DELETE, &nidw);
            }
		}

		void mainForm_VisibleChanged (Object sender, EventArgs evt) {
			// Покажем/скроем иконку в трее в зависимости от состояния окна
			nidw.dwState = NIS_HIDDEN & this.visible;
			Shell_NotifyIconW(NIM_MODIFY, &nidw);
		}

		checkBox2.click.addHandler(&checkBox2_Clicked);
		button5.click.addHandler(&button5_Clicked);
		button6.click.addHandler(&button6_Clicked);
		button7.click.addHandler(&button7_Clicked);
		this.load.addHandler(&mainForm_Loaded);
		this.closing.addHandler(&mainForm_Closing);
		this.visibleChanged.addHandler(&mainForm_VisibleChanged);
	}

	// Лучше вынести в DFL?
	protected override void wndProc(ref Message m) {
		if (m.msg == 0x9090) {
			switch (m.lParam) {
				case 0x202:
				case 0x205:
				case 0x208:
					writefln("Tray icon clicked");
					if (!this.visible) {
						this.show();
						this.focus();
                    }
					break;
				default:
			}
        }
		super.wndProc(m);
    }

	public static MainForm getInstance() {
		return instance;
    }
}