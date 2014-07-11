hubot-streetfood
=================

Hubot plugin to locate food carts
Uses data from http://streetfoodapp.com
Ranks food carts based on distance, rating, and if they're open

## Installation

### Update the files to include the hubot-streetfood module:

#### package.json
    ...
    "dependencies": {
      ...
      "hubot-streetfood": ">= 0.1.0"
      ...
    },
    ...

#### external-scripts.json
    [...,"hubot-streetfood"]

Run `npm install` to install hubot-streetfood and dependencies.

Commands
-----
```
hubot streetfood - choose a random (weighted based on score) food cart
hubot food cart - choose a random (weighted based on score) food cart
hubot food cart in vancouver - choose a random (weighted based on score) food cart in Vancouver
hubot top 5 food carts - list top 5 food carts in default city, sorted by score
hubot top 5 food carts in calgary - list top 5 food carts in calgary, sorted by score
```
