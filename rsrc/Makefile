NO_COLOR    = \x1b[0m
BUILD_COLOR    = \x1b[32;01m
CLEAN_COLOR    = \x1b[31;01m


FILES:=$(patsubst %.svg,%.png,$(wildcard *.svg))
DIRS:=$(wildcard ../*)
	
all: $(FILES)

%.png : %.svg
	@echo -e '$(BUILD_COLOR)* Rendering [$@]$(NO_COLOR)' 
	inkscape $< -z --export-dpi=96 -e=$@ 2>/dev/null

	case "$(patsubst %.png,%.install,$@)" in zero-lliurex-recursos-*) if [ ! -e ../$(patsubst %.png,%.install,$@) ];then ln -s zero-lliurex-recursos.install ../$(patsubst %.png,%.install,$@); fi ;; esac
	@echo -e '$(BUILD_COLOR)* Copying $@ to ../$(patsubst %.png,%.install,$@)/usr/share/banners/lliurex-neu/$(NO_COLOR)' 
	cp $@ ../$(patsubst %.png,%.install,$@)/usr/share/banners/lliurex-neu/
	
clean:
	@echo -e '$(CLEAN_COLOR)* Cleaning...$(NO_COLOR)'
	rm -rf $(patsubst %.svg,%.png,$(wildcard *.svg))
	
	
