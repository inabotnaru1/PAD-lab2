FROM ruby:2.5-alpine3.11
WORKDIR /app
COPY . /app/
COPY . .

RUN apk update && apk add --virtual build-dependencies build-base
RUN apk add libxslt-dev libxml2-dev

RUN gem install bundler
RUN bundle

EXPOSE 8000

CMD ruby main.rb