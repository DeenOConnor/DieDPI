module mainform;

import cfg;
import std.conv : to;
import dfl.all;
static import utils;
import settingsform;
import tools : startTool, stopTool;
static import updater;

class MainForm: Form {
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
	private static bool isRunning = false; 
	
	
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
	}
	
	
	private void initializeMyForm() {
		this.text = "DieDPI v0.0.0";
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
		label6.text = "Тестовая версия!";
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
			//ConfigManager.setUpdateNeeded(true);
			if (updater.selfUpdateNeeded()) {
				updater.downloadUpdate();
				msgBox("Обновление загружено и будет установлено при следующем запуске"w, "Обновление"w, MsgBoxButtons.OK, MsgBoxIcon.INFORMATION);
            } else {
				msgBox("Обновлений не обнаружено"w, "Обновление"w, MsgBoxButtons.OK, MsgBoxIcon.INFORMATION);
            }
		}

		void mainForm_Loaded (Object sender, EventArgs evt) {
			auto globConf = ConfigManager.getGlobalConfig();
			if (globConf.autostart) {
				// Проставим галочку, чтобы пользователь не путался
				checkBox2.checked(true);
				if(globConf.persistentState) {
					// Если мы в автозапуске и последнее состояние было включено - включимся
					//import std.string : format;
					//msgBox(format!"enabled:%d visible:%d handleCreated:%d"w(button5.enabled, button5.visible, button5.isHandleCreated));
					button5.performClick();
                }
			}
			this.focus();
		}

		checkBox2.click.addHandler(&checkBox2_Clicked);
		button5.click.addHandler(&button5_Clicked);
		button6.click.addHandler(&button6_Clicked);
		button7.click.addHandler(&button7_Clicked);
		this.load.addHandler(&mainForm_Loaded);
	}
}