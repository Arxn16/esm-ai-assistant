FROM ruby:2.3
RUN echo "deb http://archive.debian.org/debian stretch main" > /etc/apt/sources.list && \
    echo "deb http://archive.debian.org/debian-security stretch/updates main" >> /etc/apt/sources.list && \
    echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends --allow-unauthenticated \
        nodejs imagemagick ffmpeg wkhtmltopdf dcmtk openssl libssl-dev \
        default-libmysqlclient-dev \
        libxmlsec1-dev libxml2-dev libxslt1-dev pkg-config && \
    rm -rf /var/lib/apt/lists/*
RUN mkdir /docker_app
WORKDIR /docker_app
COPY Gemfile /docker_app/Gemfile
COPY Gemfile.lock /docker_app/Gemfile.lock
RUN gem install bundler -v 1.17.3 --no-document && bundle _1.17.3_ install
COPY . /docker_app

# Add a script to be executed every time the container starts.
COPY entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]
EXPOSE 3000

ENV TZ=Asia/Bangkok
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone


# Start the main process.
#CMD ["rails", "server", "-b", "0.0.0.0", "-e", "production"]


