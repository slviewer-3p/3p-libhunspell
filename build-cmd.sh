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
            opts="-m$AUTOBUILD_ADDRSIZE -arch $AUTOBUILD_CONFIGURE_ARCH $LL_BUILD_RELEASE"
            export CFLAGS="$opts"
            export CXXFLAGS="$opts"
            export LDFLAGS="$opts"
            # nat 2016-03-21: If configure / make is allowed to build dylibs,
            # it fails because although the makefile does pass -stdlib=libc++
            # (from LL_BUILD_RELEASE) to the individual compile commands and to the
            # local generated libtool script, libtool fails to pass it through
            # to the link command. That means that the linker is trying to
            # link a dylib against the (old, no longer supported) libstdc++
            # rather than libc++ with which the object files were compiled,
            # leading to strange standard-library-related link errors.
            # Fortunately, the viewer doesn't actually consume dylibs, so
            # suppress them to bypass this weird problem. If it did, we'd be
            # in the unfortunate position of trying to diagnose just why
            # autoconf's libtool swallows the -stdlib switch in link mode.
            ./configure --prefix="$stage" --disable-shared
            make
            make install
            mkdir -p "$stage/lib/release"
            mv "$stage/lib/"*.a "$stage/lib/release"
        ;;
        linux*)
            opts="-m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE"
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
