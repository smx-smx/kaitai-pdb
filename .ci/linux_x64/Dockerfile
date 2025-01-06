FROM debian:bookworm

RUN apt-get update \
	&& apt-get install --no-install-recommends -y php php-cli composer locales ca-certificates curl git libarchive-tools default-jdk-headless \
	&& localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8 \
	&& curl -Lo - https://github.com/kaitai-io/kaitai_struct_compiler/releases/download/0.10/kaitai-struct-compiler-0.10.zip |\
		bsdtar -xvf- -C /opt/ \
	&& chmod +x /opt/kaitai-struct-compiler-0.10/bin/kaitai-struct-compiler \
	&& echo 'export PATH=$PATH:/opt/kaitai-struct-compiler-0.10/bin' >> /etc/bash.bashrc \
    && curl -O https://dotnet.microsoft.com/download/dotnet/scripts/v1/dotnet-install.sh \
    && bash dotnet-install.sh --channel 6.0 \
    && bash dotnet-install.sh --channel 8.0 \
    && mv /root/.dotnet /usr/share/dotnet \
    && ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && dotnet nuget locals all --clear
	# reserved for cache eviction: 1

ENV LANG en_US.utf8