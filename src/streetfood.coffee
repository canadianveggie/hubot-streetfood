# Description:
#   Locates food carts and makes a suggestion based on who is open, distance, and rating
#
# Dependencies:
#   None
#
# Configuration:
#   HUBOT_STREETFOOD_API_KEY - Street Food App API key
#   HUBOT_STREETFOOD_DEFAULT_CITY - City to find food carts in
#   HUBOT_STREETFOOD_DEFAULT_LAT - Latitude to score food carts from
#   HUBOT_STREETFOOD_DEFAULT_LNG - Longitude to score food carts from
#
# Commands:
#   hubot streetfood|food cart (in CITY) - Suggest a food cart
#   hubot top N streetfood| food carts (in CITY) - List top N food carts
#
# Author:
#   canadianveggie

web_url = 'http://streetfoodapp.com/'
api_url = "http://data.streetfoodapp.com/1.1/"

default_location = {
  city: process.env.HUBOT_STREETFOOD_DEFAULT_CITY,
  latitude: process.env.HUBOT_STREETFOOD_DEFAULT_LAT,
  longitude: process.env.HUBOT_STREETFOOD_DEFAULT_LNG
}

user_agent = "Hubot Streetfood Engine"

vendorCache = {}

getVendors = (robot, city, callback) ->
  now = new Date().getTime()
  city = city.toLowerCase().replace(/\W/g, "-",)
  if city of vendorCache and vendorCache[city].expires > now
    return callback(null, vendorCache[city].vendors)

  robot.http("#{api_url}schedule/#{city}/")
    .headers("User-Agent": user_agent: "Accept": "application/json")
    .get() (err, res, body) ->
      return callback(err or body) if err or res.statusCode < 200 or res.statusCode >= 300

      vendors = (JSON.parse body).vendors
      vendors = (v for k,v of vendors)
      vendorCache[city] = vendors : vendors, expires : now + 1000*60*5 # 5 minute expiry
      callback(err, vendors)

calculateOpenStateAndScore = (vendor, now) ->
  now or= new Date().getTime()
  if vendor.open?.length > 0
    nextOpen = vendor.open[0].start * 1000
    nextClose = vendor.open[0].end * 1000
    if nextOpen < now and nextClose > now + 30*60*1000 # open for next 30 minutes
      return score:1, state:"Open"
    else if nextOpen < now + 15*60*1000 and nextClose > now + 30*60*1000 # opening in next 15 minutes
      return score:0.8, state:"Opening Soon"
    else if nextOpen < now + 15*60*1000 and nextClose > now # closing soon
      return score:0.5, state:"Closing Soon"
    else
      return score:0.001, state:"Closed" # closed
  else
    return score:0, state:"Long Term Closure" # permanently closed?

calculateDistance = (vendor, latitude, longitude) ->
  if latitude? and longitude? and vendor.open?.length
    vendorLatitude = vendor.open[0].latitude
    vendorLongitude = vendor.open[0].longitude
    x_dist = (longitude - vendorLongitude) * Math.cos(vendorLatitude / 360 * 2 * Math.PI) * 110.54 # km
    y_dist = (latitude - vendorLatitude) * 111.320 # km
    # return Math.sqrt(x_dist*x_dist + y_dist*y_dist) #Euclidean distance
    return Math.abs(x_dist) + Math.abs(y_dist) # Manhattan distance
  else
    return 0 # assume distance is 0 if we can't calculate it

formatDistance = (distance) ->
  if distance == 0
    return "unknown"
  else if distance < 1
    return "#{Math.round(distance * 1000)} meters"
  else
    return "#{Math.round(distance *10) / 10} km"

formatUrl = (vendor, city) ->
  return "#{web_url}#{city}/#{vendor.identifier}"

scoreVendors = (vendors, latitude, longitude) ->
  now = new Date().getTime()
  scores = []
  for vendor in vendors
    openScoreAndState = calculateOpenStateAndScore(vendor, now)
    distance = calculateDistance(vendor, latitude, longitude)
    distanceScore = Math.pow(10, -1 * distance)
    ratingScore = Math.log(Math.max(vendor.rating, 1))

    scores.push score: openScoreAndState.score * distanceScore * ratingScore, open: openScoreAndState.state, distance: formatDistance(distance), vendor:vendor
  return scores

chooseVendor = (scoredVendors) ->
  totalScore = scoredVendors.reduce (total, vendor) ->
    total + vendor.score
  , 0
  choose = Math.random() * totalScore
  for scoredVendor in scoredVendors
    choose -= scoredVendor.score
    if choose < 0
      return scoredVendor
  return undefined

msgVendorInfo = (msg, scoredVendor, city) ->
  vendorInfo = "#{scoredVendor.vendor.name} - #{scoredVendor.open}"
  if scoredVendor.distance != "unknown"
    vendorInfo += " - #{scoredVendor.distance}"
  vendorInfo += " - #{scoredVendor.vendor.rating} fans - #{formatUrl(scoredVendor.vendor, city)}"
  msg.send vendorInfo

msgVendorDetails = (msg, vendor) ->
  if vendor.description
    msg.send vendor.description
  if vendor.open?.length and vendor.open[0].special
    msg.send "*** #{vendor.open[0].special} ***"
  if vendor.images?.header?.length
    msg.send msg.random vendor.images.header

getLocationDetails = (robot, location_request, callback) ->
  return callback default_location unless location_request
  geoLookup(robot, location_request, callback)


geoLookup = (robot, location_request, callback) ->
    robot.http("https://maps.googleapis.com/maps/api/geocode/json")
      .header('User-Agent': user_agent)
      .query({
        address: location_request
        sensor: false
      })
      .get() (err, res, body) ->
        return callback {} if err or res.statusCode < 200 or res.statusCode >= 300

        response = JSON.parse(body)
        return callback {} unless response.results?.length

        city = response.results[0].address_components.filter (c) -> "locality" in c.types

        return callback {} unless city?.length
        return callback {
          city: city[0].short_name,
          latitude: response.results[0].geometry.location.lat,
          longitude: response.results[0].geometry.location.lng
        }

module.exports = (robot) ->
  robot.respond /(street( )?food|food( )?cart(s)?)( (in|near) (.+))?/i, (msg) ->
    getLocationDetails robot, msg.match[7], (location) ->
      return msg.send "I don't know where look for food carts" unless location.city

      getVendors robot, location.city, (error, vendors) ->
        return msg.send "No food carts found in #{location.city}" unless vendors?.length

        scoredVendors = scoreVendors(vendors, location.latitude, location.longitude)
        choice = chooseVendor(scoredVendors)

        return msg.send "Sorry, I couldn't find any food carts" unless choice?

        msgVendorInfo msg, choice, location.city
        msgVendorDetails msg, choice.vendor

  robot.respond /top (\d+) (street( )?food|food( )?cart(s)?)( (in|near) (.+))?/i, (msg) ->
    n = +msg.match[1]
    getLocationDetails robot, msg.match[8], (location) ->
      return msg.send "I don't know where look for food carts" unless location.city

      getVendors robot, location.city, (error, vendors) ->
        return msg.send "No food carts found in #{location.city}" unless vendors?.length

        scoredVendors = scoreVendors(vendors, location.latitude, location.longitude)
        scoredVendors = scoredVendors.filter (a) -> return a.score > 0
        scoredVendors.sort (a,b) -> return b.score - a.score
        topN = scoredVendors.slice(0, n)
        for scoredVendor in topN
          msgVendorInfo msg, scoredVendor, location.city

