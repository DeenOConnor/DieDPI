module settingsform;

// Взаимодействуем с настройками только через эти функции
import cfg;
import tools;
import std.stdio : writeln, writefln;

import dfl.all;
import autosetupform;

class SettingsForm: dfl.form.Form
{
	dfl.button.Button button8;
	dfl.button.CheckBox checkBox3;
	dfl.groupbox.GroupBox groupBox2;
	dfl.label.Label label7;
	dfl.combobox.ComboBox comboBox4;
	dfl.label.Label label8;
	dfl.combobox.ComboBox comboBox5;
	dfl.label.Label label9;
	dfl.combobox.ComboBox comboBox6;
	dfl.groupbox.GroupBox groupBox3;
	dfl.label.Label label10;
	dfl.textbox.TextBox textBox3;
	dfl.label.Label label11;
	dfl.textbox.TextBox textBox4;
	dfl.label.Label label12;
	dfl.textbox.TextBox textBox5;
	dfl.button.Button button12;
	dfl.button.Button button10;
	
	this()
	{
		initializeSettings();
	}
	
	
	private void initializeSettings()
	{
		this.text = "Настройки";
		this.clientSize = dfl.all.Size(360, 197);
		this.maximizeBox = false;
		this.formBorderStyle = FormBorderStyle.FIXED_SINGLE;

		button8 = new dfl.button.Button();
		button8.name = "button8";
		button8.text = "Автонастройка";
		button8.bounds = dfl.all.Rect(8, 8, 347, 63);
		button8.parent = this;

		groupBox2 = new dfl.groupbox.GroupBox();
		groupBox2.name = "groupBox2";
		groupBox2.text = "Обычные настройки";
		groupBox2.bounds = dfl.all.Rect(8, 112, 344, 52);
		groupBox2.parent = this;

		label7 = new dfl.label.Label();
		label7.name = "label7";
		label7.text = "Инструмент обхода:";
		label7.textAlign = dfl.all.ContentAlignment.MIDDLE_LEFT;
		label7.bounds = dfl.all.Rect(8, 19, 108, 23);
		label7.parent = groupBox2;

		comboBox4 = new dfl.combobox.ComboBox();
		comboBox4.name = "comboBox4";
        comboBox4.dropDownStyle = ComboBoxStyle.DROP_DOWN_LIST;
		comboBox4.bounds = dfl.all.Rect(120, 19, 208, 21);
		comboBox4.parent = groupBox2;

		checkBox3 = new dfl.button.CheckBox();
		checkBox3.name = "checkBox3";
		checkBox3.text = "Расширенные настройки (для опытных пользователей)";
		checkBox3.bounds = dfl.all.Rect(8, 168, 347, 23);
		checkBox3.parent = this;

		groupBox3 = new dfl.groupbox.GroupBox();
		groupBox3.name = "groupBox3";
		groupBox3.enabled = false;
		groupBox3.visible = false;
		groupBox3.text = "Расширенные настройки";
		groupBox3.bounds = dfl.all.Rect(8, 192, 344, 132);
		groupBox3.parent = this;

		label11 = new dfl.label.Label();
		label11.name = "label11";
		label11.text = "URL запроса версии:";
		label11.textAlign = dfl.all.ContentAlignment.MIDDLE_LEFT;
		label11.bounds = dfl.all.Rect(8, 19, 108, 23);
		label11.parent = groupBox3;

		textBox4 = new dfl.textbox.TextBox();
		textBox4.name = "textBox4";
		textBox4.text = "https://raw.githubusercontent.com/DeenOConnor/DieDPI/refs/heads/master/ver";
		textBox4.bounds = dfl.all.Rect(8, 43, 320, 23);
		textBox4.parent = groupBox3;

		label12 = new dfl.label.Label();
		label12.name = "label12";
		label12.text = "URL загрузки обновлений:";
		label12.textAlign = dfl.all.ContentAlignment.MIDDLE_LEFT;
		label12.bounds = dfl.all.Rect(8, 75, 140, 23);
		label12.parent = groupBox3;

		textBox5 = new dfl.textbox.TextBox();
		textBox5.name = "textBox5";
		textBox5.text = "https://api.github.com/repos/DeenOConnor/DieDPI/releases";
		textBox5.bounds = dfl.all.Rect(8, 99, 320, 23);
		textBox5.parent = groupBox3;

		button10 = new dfl.button.Button();
		button10.name = "button10";
		button10.text = "Остановить и удалить";
		button10.bounds = dfl.all.Rect(8, 80, 347, 23);
		button10.parent = this;

		foreach (tool, link; TOOLS) {
			comboBox4.items.add(tool);
        }

		void button8_Clicked (Object sender, EventArgs evt) {
			msgBox(
"Экспериментальная функция!
Может приводить к ошибкам и работать нестабильно!
Используйте автонастройку на свой страх и риск!"w,
			"Внимание!"w, MsgBoxButtons.OK, MsgBoxIcon.WARNING);
			new AutoSetupForm().show();
		}

		void button10_Clicked (Object sender, EventArgs evt) {
			auto result = msgBox(
"Инструмент будет остановлен (если запущен) и удалён.
Обычно в этом нет необходимости, но можно попробовать, если обход не запускается.
После удаления инструмента, при попытке запустить обход с ним, он будет скачан заново."w,
			"Удаление"w, MsgBoxButtons.OK_CANCEL, MsgBoxIcon.QUESTION);
			writeln(result);
			if (result == DialogResult.OK) {
				try {
					import std.conv;
					import std.file;
					import std.uni;
					if (!stopTool()) {
						throw new Exception("Could not stop tool");
                    }
					rmdirRecurse(".\\tools\\" ~ to!string(toLower(TOOLS.keys[ConfigManager.getGlobalConfig().tool])));
                } catch (Exception ex) {
					
                }
            }
        }

		void checkBox3_Clicked (Object sender, EventArgs evt) {
			if (checkBox3.checked()) {
				// Т.к. здесь идёт закачка архива с обновлениями, нужно убедиться что юзер испугается страшных диалоговых окон и не будет ничего трогать
				// А то мало ли вредоносная ссылка на "обновление" с троянами - мы всё-таки от имени администратора тут работаем
				auto res = msgBox("Изменение этих настроек может, в числе прочего:
 - Сломать обход
 - Испортить работу интернета
 - Привести к скачиванию и запуску сторонних программ
Если вы действуете по чужой инструкции, подумайте ещё раз, доверяете ли вы автору(ам)!
Если вы не уверены что чётко понимаете что и зачем делаете, заблокируйте настройки до перезапуска.

Вы хотите заблокировать доступ к раширенным настройкам?"w, "Внимание!"w, MsgBoxButtons.YES_NO, MsgBoxIcon.WARNING);
				writefln("DialogResult %d", cast(ubyte)res);
				if (res == DialogResult.YES || res == DialogResult.OK) {
					// Если юзер не понял или жмакнул не глядя, снимем и заблочим галочку до перезапуска
					checkBox3.checked(false);
					checkBox3.enabled(false);
					return;
                }
            }
			this.clientSize = dfl.all.Size(360, 197 + (groupBox3.height + 4) * cast(uint) checkBox3.checked());
			groupBox3.enabled = checkBox3.checked();
			groupBox3.visible = checkBox3.checked();
		}

		void comboBox4_selectedValueChanged (Object sender, EventArgs evt) {
			auto ind = comboBox4.selectedIndex();
			if (ind >= 0 && ind <= 255) {
				ConfigManager.setTool(cast(ubyte)comboBox4.selectedIndex());
			}
		}

		void settingsForm_Loaded (Object sender, EventArgs evt) {
			// Для изменения выбора нужно чтобы был хендл
			ubyte tool;
			synchronized {
				tool = (cast(Config)ConfigManager.getGlobalConfig()).tool;
			}
			comboBox4.selectedIndex(tool);
		}

		void settingsForm_Closing (Object sender, EventArgs evt) {
			// Сделаем так, чтобы форма не удалялась, а просто скрывалась
			ConfigManager.writeConfig();
			this.hide();
			if (auto cea = cast(CancelEventArgs) evt) {
				cea.cancel = true;
            }
		}

		button8.click.addHandler(&button8_Clicked);
		button10.click.addHandler(&button10_Clicked);
		checkBox3.click.addHandler(&checkBox3_Clicked);
		comboBox4.selectedValueChanged.addHandler(&comboBox4_selectedValueChanged);
		this.load.addHandler(&settingsForm_Loaded);
		this.closing.addHandler(&settingsForm_Closing);
	}
}

