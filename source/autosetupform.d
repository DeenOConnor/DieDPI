module autosetupform;

import std.concurrency;
import std.stdio;
import core.thread;

import dfl.all;

import cfg;
import mainform;
import network;
import tools;
import utils;

class AutoSetupForm: Form
{
	TextBox textBox1;
	ProgressBar progressBar1;
	Button button1;

	__gshared private static Tid mainTid;
	__gshared static Thread workerThread;
	
	this()
	{
		initializeMyForm();
	}
	
	
	private void initializeMyForm()
	{
		this.text = "Автонастройка";
		this.clientSize = dfl.all.Size(480, 175);
		this.maximizeBox = false;
		this.formBorderStyle = FormBorderStyle.FIXED_SINGLE;

		textBox1 = new dfl.textbox.TextBox();
		textBox1.name = "textBox1";
		textBox1.backColor = dfl.all.SystemColors.control;
		textBox1.enabled = true;
		textBox1.text = "Рекомендуемые настройки не всегда помогают. Некоторым провайдерам требуется особый подход. Автонастройка попытается подобрать параметры обхода DPI прямо на месте, на случай если нужные сайты не работают.\r\nВНИМАНИЕ! Автонастройка перебирает все возможные параметры, поэтому процесс может занять длительное время! Полный прогон вполне может занять в районе часа, и даже больше. Во избежание сбоев настоятельно рекомендуется не закрывать окно автонастройки, пока она не завершится.";
		textBox1.borderStyle = dfl.all.BorderStyle.NONE;
		textBox1.multiline = true;
		textBox1.readOnly = true;
		textBox1.bounds = dfl.all.Rect(8, 8, 456, 97);
		textBox1.parent = this;

		progressBar1 = new dfl.progressbar.ProgressBar();
		progressBar1.name = "progressBar1";
		progressBar1.bounds = dfl.all.Rect(8, 114, 460, 23);
		progressBar1.value = 0;
		progressBar1.step = 1;
		progressBar1.parent = this;

		button1 = new dfl.button.Button();
		button1.name = "button4";
		button1.text = "Запуск";
		button1.bounds = dfl.all.Rect(8, 146, 459, 23);
		button1.parent = this;
		button1.notifyDefault(true);
		button1.focus();

		void button1_Clicked (Object sender, EventArgs evt) {
            try {
                if (MainForm.isRunning) {
                    msgBox("Обход будет выключен для проведения автонастройки!"w, ""w, MsgBoxButtons.OK, MsgBoxIcon.WARNING);
                    MainForm.getInstance().button5.performClick();
                }

                progressBar1.value = 0;
                button1.enabled = false;
                button1.text = "Идёт автонастройка"w;

                // Сделаем так, иначе сообщения из очереди перестанут разбираться и интерфейс повиснет
                mainTid = thisTid();
                workerThread = new Thread(&doAutosetup).start();
            } catch (Exception ex) {
                if (workerThread && workerThread.isRunning()) {
                    
                }
                //Application.onThreadException(ex);
                printFormattedException(ex);
            }
		}
		button1.click.addHandler(&button1_Clicked);
        
        void autosetupForm_Loaded (Object sender, EventArgs evt) {
            button1.focus();
        }
		this.load.addHandler(&autosetupForm_Loaded);
	}

	private static void progressTick() {
		debug {
            try {
                writeln("ping");
            } catch (Exception ex) {
                Application.onThreadException(ex);
            }
        }
		send(mainTid, 0x9090);
    }

	private static void doAutosetup() {
    try {        
        bool result = false;
        try {
            // Т.к. у нас новый поток, надо пересоздать хендлы интернета
            if (configureInternet()) {
                // Если интернет не настроился, нам нет смысла чего-то там гонять
                auto tool = ConfigManager.getGlobalConfig().tool;
                switch(tool) {
                    case 0:
                        // Пока что зашиваем общее количество попыток, в дальнейшем надо высчитывать
                        send(mainTid, 150);
                        result = autosetupGoodbyeDPI(2, &progressTick);
                        break;
                    case 1:
                        send(mainTid, 120);
                        result = autosetupZapret(2, &progressTick);
                        break;
                    default:
                        writeln("Could not get the active tool!");
                        msgBox("Не удалось запустить автонастройку"w, "Автонастройка"w, MsgBoxButtons.OK, MsgBoxIcon.ERROR);
                        return;
                }
            }
            // Вызывает переполнение стека
            //send(mainTid, 0x8080);

            Thread.sleep(dur!"msecs"(15));
        } catch (Exception ex) {
            printFormattedException(ex);
        }
		if (result) {
			msgBox("Автонастройка завершена, настройки применены"w, "Автонастройка"w, MsgBoxButtons.OK, MsgBoxIcon.INFORMATION);
        } else {
			msgBox("Автонастройка завершилась сбоем, настройки не изменены"w, "Автонастройка"w, MsgBoxButtons.OK, MsgBoxIcon.ERROR);
        }
        
        mainTid = Tid.init;
        } catch (Throwable t) {
            writefln("A critical error occured in a thread:\n", t.toString());
        }
    }

	override void wndProc(ref Message m) {
		// Здесь будем пытаться принимать тычки от рабочего потока, при этом не мешая обработке сообщений
		try {
            if (workerThread && workerThread.isRunning()) {
                char[64] tta, mta;
                auto ttaa = cast(char[])tta;
                auto mtaa = cast(char[])mta;
                thisTid.toString!(char[])(ttaa);
                mainTid.toString!(char[])(mtaa);
                string tts = tta.idup;
                string mts = mta.idup;
                if (tts != mts) {
                    writefln("This: %s, main: %s", tta[], mta[]);
                }
                if (tts == mts && workerThread !is null) {
                    //if () {
                        if (workerThread.isRunning) {
                            try {
                                receiveTimeout(
                                    dur!"usecs"(5),
                                    (int i) {
                                        switch (i) {
                                            case 0x8080:
                                                button1.text = "Запуск"w;
                                                button1.enabled = true;
                                                progressBar1.value = progressBar1.maximum;
                                                break;
                                            case 0x9090:
                                                progressBar1.performStep();
                                                break;
                                            default:
                                                progressBar1.maximum = i;
                                        }
                                    }
                                );
                            } catch (OwnerTerminated ex) {
                                writeln("Owner terminated");
                                workerThread = null;
                                Application.onThreadException(ex);
                                return;
                            }
                        } else if (!workerThread.isRunning && false) {
                            // Считаем что поток завершился
                            button1.text = "Запуск"w;
                            button1.enabled = true;
                            progressBar1.value = progressBar1.maximum;
                        }
                    //}
                }
            }
		} catch (Exception ex) {
			printFormattedException(ex);
            workerThread = null;
        }
        
        super.wndProc(m);
    }
}