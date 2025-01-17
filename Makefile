CLANG ?= clang
CLANG-FORMAT ?= clang-format
CPPCHECK ?= cppcheck
SCAN-BUILD ?= scan-build
GCC ?= gcc
VALGRIND ?= valgrind

THIS_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
PROJECT_SRC_DIR ?= $(THIS_DIR)project

CLANG_FLAGS_COMMON += -D__NR_CPUS__=$(NPROC) -O2
CLANG_INCLUDES_COMMON += -I. -I$(PROJECT_SRC_DIR)/libbpf/include

GTK := gtk+-3.0
GTK_CFLAGS := $(shell pkg-config --cflags $(GTK))
GTK_INCLUDE := $(shell pkg-config --libs $(GTK))

CLANG_FLAGS_PROJECT += -L$(PROJECT_SRC_DIR) $(CLANG_FLAGS_COMMON) $(GTK_CFLAGS) -lcurl -l$(CJSON) -Wall -Wextra -Wshadow -Wpedantic
CLANG_INCLUDES_PROJECT += $(CLANG_INCLUDES_COMMON) $(GTK_INCLUDE)

NPROC := $(shell nproc)
PROJECT_FILES := $(shell find $(PROJECT_SRC_DIR) -type f -name "*.c" -or -name "*.h")

CURRENT_KERNEL := $(shell uname -r | sed "s/[-].*$\//")
PROJECT_OBJECT := output_bin


# all: installation_doc sanitize format build

all: build

installation_doc:
	echo "hi $(CURRENT_KERNEL)\n";

UNAME_S := $(shell uname -s)
# Verify that compiler and tools are available
ifeq ($(UNAME_S), Darwin)
CJSON := cJSON
.PHONY: verify_cmds $(CLANG) $(CPPCHECK) $(CLANG-FORMAT) $(GCC)
verify_cmds: $(CLANG) $(CPPCHECK) $(CLANG-FORMAT) $(GCC)
else
CJSON := cjson
.PHONY: verify_cmds $(CLANG) $(CPPCHECK) $(CLANG-FORMAT) $(GCC) $(SCAN-BUILD) $(VALGRIND)
verify_cmds: $(CLANG) $(CPPCHECK) $(CLANG-FORMAT) $(GCC) $(SCAN-BUILD) $(VALGRIND)
endif
	@for TOOL in $^ ; do \
		if ! (which -- "$${TOOL}" > /dev/null 2>&1); then \
			echo "*** ERROR: Cannot find tool $${TOOL}" ;\
			exit 1; \
		else true; fi; \
	done

sanitize: verify_cmds
	@if ! (printf "[1/6 clang] \n\n" && ${CLANG} $(CLANG_FLAGS_PROJECT) --analyze $(PROJECT_SRC_DIR)/main.c) || \
				! (printf "[2/6 clang] \n\n" && ${CLANG} $(CLANG_FLAGS_PROJECT) $(CLANG_INCLUDES_PROJECT) -fsanitize=memory,undefined,integer -fsanitize-memory-track-origins=2 \
						-fno-omit-frame-pointer -fsanitize-memory-use-after-dtor \
						-g -O2 $(PROJECT_SRC_DIR)/main.c) || \
				! (printf "[3/6 clang] \n\n" && ${CLANG} $(CLANG_FLAGS_PROJECT) $(CLANG_INCLUDES_PROJECT) -fsanitize=address -fno-omit-frame-pointer -g -O2 $(PROJECT_SRC_DIR)/main.c) || \
				! (printf "[4/6 scan-build] \n\n" && ${SCAN-BUILD} -V gcc -c $(PROJECT_SRC_DIR)/main.c 2>&1 | grep -vE '/usr/bin/scan-build line 1860.') || \
				! (printf "[5/6 cppcheck] \n\n" && ${CPPCHECK} $(PROJECT_SRC_DIR) -j $(NPROC) --template=gcc --language=c --std=c99 --std=posix \
						--platform=unix64 --enable=all --inconclusive --report-progress --verbose --force --check-library \
						-I/usr/include -I/usr/include/linux -I/usr/lib/gcc/x86_64-linux-gnu/7/include 2>&1 | grep -vE '__|There is no|equals another one|Checking|information:|scope') || \
				! (printf "[6/6 gcc] \n\n" && ${GCC} $(CLANG_FLAGS_PROJECT) $(CLANG_INCLUDES_PROJECT) -Wall -Wextra -Wpedantic -Wshadow -Wno-unused-but-set-variable $(PROJECT_SRC_DIR)/main.c); then \
		echo "*** ERROR: sanitize failed" ;\
		exit 2; \
	else true; fi

format: verify_cmds
	@for FILE in $(PROJECT_FILES) ; do \
		if ! ($(CLANG-FORMAT) -style='Webkit' "$${FILE}" > /tmp/test && diff "$${FILE}" /tmp/test); then \
			echo "*** ERROR: consider $(CLANG-FORMAT) -verbose -style='Webkit' "$${FILE}" > /tmp/test && mv /tmp/test "$${FILE}"" ;\
			exit 3; \
		else true; fi; \
	done

build: $(CLANG)
	$(CLANG) $(CLANG_FLAGS_PROJECT) $(CLANG_INCLUDES_PROJECT) $(PROJECT_SRC_DIR)/main.c -o $(PROJECT_OBJECT)

clean:
	rm -f $(PROJECT_OBJECT) a.out main.o main.plist

