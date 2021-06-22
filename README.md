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

# Run with GNU Guix

```
source .guix-deploy
puma

Puma starting in single mode...

* Puma version: 5.3.2 (ruby 2.6.5-p114) ("Sweetnighter")
*  Min threads: 0
*  Max threads: 16
*  Environment: production
* Listening on http://0.0.0.0:9292

```

To run the development version:

```
puma -t 1 -e development
```

or for more info

```
puma -t 1 -e development --redirect-stderr /dev/stdout \
  --redirect-stdout /dev/stdout -w 0 -v
```
