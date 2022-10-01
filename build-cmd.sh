#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# complain about unset env variables
set -u

HUNSPELL_SOURCE_DIR="hunspell"
# Look in configure script for line PACKAGE_VERSION='x.y.z', then capture
# everything between single quotes.
HUNSPELL_VERSION="$(expr "$(grep '^PACKAGE_VERSION=' "$HUNSPELL_SOURCE_DIR/configure")" \
                         : ".*'\(.*\)'")"

if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

stage="$(pwd)/stage"

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

build=${AUTOBUILD_BUILD_ID:=0}
echo "${HUNSPELL_VERSION}.${build}" > "${stage}/VERSION.txt"

pushd "$HUNSPELL_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        windows*)
            load_vsvars

            build_sln "src/win_api/hunspell.sln" "Release_dll|$AUTOBUILD_WIN_VSPLATFORM"

            mkdir -p "$stage/lib/release"

            if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
            then bitdir=src/win_api/Release_dll/libhunspell/libhunspell
            else bitdir=src/win_api/x64/Release_dll/libhunspell
            fi

            cp "$bitdir"{.dll,.lib,.pdb} "$stage/lib/release"
        ;;
        darwin*)
            opts="${AUTOBUILD_GCC_ARCH} -arch $AUTOBUILD_CONFIGURE_ARCH $LL_BUILD_RELEASE"
            export CFLAGS="$opts"
            export CXXFLAGS="$opts"
            export LDFLAGS="$opts"
            ./configure --prefix="$stage"
            make
            make install
            mkdir -p "$stage/lib/release"
            mv "$stage/lib/"{*.a,*.dylib,*.alias} "$stage/lib/release"
            pushd "$stage/lib/release"
                fix_dylib_id libhunspell-*.dylib
              
                CONFIG_FILE="$build_secrets_checkout/code-signing-osx/config.sh"
                if [ -f "$CONFIG_FILE" ]; then
                    source $CONFIG_FILE
                    for dylib in libhunspell-*.dylib;
                    do
                        if [ -f "$dylib" ]; then
                            codesign --force --timestamp --sign "$APPLE_SIGNATURE" "$dylib"
                        fi
                    done
                else
                    echo "No config file found; skipping codesign."
                fi
            popd
        ;;
        linux*)
            opts="${AUTOBUILD_GCC_ARCH} $LL_BUILD_RELEASE"
            CFLAGS="$opts" CXXFLAGS="$opts" ./configure --prefix="$stage"
            make
            make install
            mv "$stage/lib" "$stage/release"
            mkdir -p "$stage/lib"
            mv "$stage/release" "$stage/lib"
        ;;
    esac
    mkdir -p "$stage/include/hunspell"
    cp src/hunspell/{*.h,*.hxx} "$stage/include/hunspell"
    cp src/win_api/hunspelldll.h "$stage/include/hunspell"
    mkdir -p "$stage/LICENSES"
    cp "license.hunspell" "$stage/LICENSES/hunspell.txt"
    cp "license.myspell" "$stage/LICENSES/myspell.txt"
popd
