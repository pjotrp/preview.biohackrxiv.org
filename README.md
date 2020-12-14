# Webapp in Ruby/Sinatra/Puma/Nginx for preview.biohackrxiv.org

For testing:

```
$ git clone https://github.com/biohackrxiv/preview.biohackrxiv.org
$ cd preview.biohackrxiv.org
$ docker-compose up --build
```

To run on background:

```
$ docker-compose up -d --build
```

Stop and remove containers:

```
$ docker-compose down
```
