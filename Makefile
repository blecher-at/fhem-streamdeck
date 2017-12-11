# makefile to create .dist directory from local fhem installation

ROOT=$(PWD)
RELATIVE_PATH=YES
BINDIR=/opt/fhem
MODDIR=$(BINDIR)/FHEM
DISTDIR=$(PWD)/.dist

dist:
	@echo $(PWD)
	rm -rf $(DISTDIR)
	mkdir $(DISTDIR)
	mkdir $(DISTDIR)/FHEM

	cp $(MODDIR)/*STREAMDECK* $(DISTDIR)/FHEM
	cd $(DISTDIR) && perl $(ROOT)/make_controlfile.pl FHEM/* > controls_streamdeck.txt
