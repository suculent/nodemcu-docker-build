# Debian/Ubuntu

sudo apt-get install make unrar-free autoconf automake libtool gcc g++ gperf \
    flex bison texinfo gawk ncurses-dev libexpat-dev python-dev python python-serial \
    sed git unzip bash help2man wget bzip2 libtool-bin

# MacOS
brew tap homebrew/dupes
brew install binutils coreutils automake wget gawk libtool help2man gperf gnu-sed --with-default-names grep
export PATH="/usr/local/opt/gnu-sed/libexec/gnubin:$PATH"

git clone --recursive https://github.com/pfalcon/esp-open-sdk.git
cd esp-open-sdk
make # (= make STANDALONE=y)
