all: tents.desktop \
     po/tents.robert-ancell.pot \
     share/locale/de/LC_MESSAGES/tents.robert-ancell.mo \
     share/locale/es/LC_MESSAGES/tents.robert-ancell.mo \
     share/locale/fr/LC_MESSAGES/tents.robert-ancell.mo \
     share/locale/it/LC_MESSAGES/tents.robert-ancell.mo \
     share/locale/nl/LC_MESSAGES/tents.robert-ancell.mo \
     share/locale/pl/LC_MESSAGES/tents.robert-ancell.mo

QML_SOURCES = FieldModel.qml FieldView.qml main.qml
FRAMEWORK = ubuntu-sdk-15.04

click: all
	click build --ignore=Makefile --ignore=*.cpp --ignore=*.h --ignore=*.pot --ignore=*.po --ignore=*.qmlproject --ignore=*.qmlproject.user --ignore=*.in --ignore=po --ignore=*.sh .

generator_moc.cpp: generator.h
	moc $< -o $@

tents.desktop: tents.desktop.in po/*.po
	intltool-merge --desktop-style po $< $@

po/tents.robert-ancell.pot: $(QML_SOURCES) tents.desktop.in
	touch po/tents.robert-ancell.pot
	xgettext --from-code=UTF-8 --language=JavaScript --keyword=tr --keyword=tr:1,2 --add-comments=TRANSLATORS $(QML_SOURCES) -o po/tents.robert-ancell.pot
	intltool-extract --type=gettext/keys tents.desktop.in
	xgettext --keyword=N_ tents.desktop.in.h -j -o po/tents.robert-ancell.pot
	rm -f tents.desktop.in.h

share/locale/%/LC_MESSAGES/tents.robert-ancell.mo: po/%.po
	msgfmt -o $@ $<

clean:
	rm -f share/locale/*/*/*.mo
	rm -r share/locale/*/*/.gitkeep
	rm -f tents.desktop

run:
	qmlscene main.qml
