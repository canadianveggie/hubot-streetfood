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

api_key = process.env.HUBOT_STREETFOOD_API_KEY
default_city = process.env.HUBOT_STREETFOOD_DEFAULT_CITY
default_lat = process.env.HUBOT_STREETFOOD_DEFAULT_LAT
default_lng = process.env.HUBOT_STREETFOOD_DEFAULT_LNG

vendorCache = {}

getVendors = (robot, city, callback) ->
  city or= default_city
  now = new Date().getTime()
  if city of vendorCache and vendorCache[city].expires > now
    return callback(null, vendorCache[city].vendors)

  auth = 'Basic ' + new Buffer("#{api_key}:").toString('base64')
  robot.http("#{api_url}schedule/#{city}/")
    .headers("Authorization": auth, "Accept": "application/json")
    .get() (err, res, body) ->
      if err or res.statusCode < 200 or res.statusCode >= 300
        callback(err or body)
      else
        vendors = (JSON.parse body).vendors
        vendors = (v for k,v of vendors)
        vendorCache[city] = vendors : vendors, expires : now + 1000*60*60 # 1 hour expiry
        callback(err, vendors)

calculateOpenStateAndScore = (vendor, now) ->
  now or= new Date().getTime()
  if vendor.open.length > 0
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
  if latitude? and longitude? and vendor.open.length > 0
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
    ratingScore = Math.log(vendor.rating)

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

msgVendorPicture = (msg, vendor) ->
  if vendor.images? and vendor.images.header and vendor.images.header.length > 0
    msg.send msg.random vendor.images.header

module.exports = (robot) ->
  robot.respond /(streetfood|food( )?cart(s)?)( in (\w+))?/i, (msg) ->
    city = default_city
    latitude = default_lat
    longitude = default_lng
    city = msg.match[5] or default_city
    if !city?
      return msg.send "I don't know what city to look for food carts in"
    city = city.toLowerCase()
    if city != default_city
      latitude = undefined
      longitude = undefined
    getVendors robot, city, (error, vendors) ->
      if !vendors?
        return msg.send "No food carts found in #{city}"
      scoredVendors = scoreVendors(vendors, latitude, longitude)
      choice = chooseVendor(scoredVendors)
      if !choice?
        return msg.send "Sorry, I couldn't find any food carts"
      msgVendorInfo msg, choice, city
      msgVendorPicture msg, choice.vendor

  robot.respond /top (\d+) (streetfood|food( )?cart(s)?)( in (\w+))?/i, (msg) ->
    n = +msg.match[1]
    latitude = default_lat
    longitude = default_lng
    city = msg.match[6] or default_city
    if !city?
      return msg.send "I don't know what city to look for food carts in"
    city = city.toLowerCase()
    if city != default_city
      latitude = undefined
      longitude = undefined
    getVendors robot, city, (error, vendors) ->
      if !vendors?
        return msg.send "No food carts found in #{city}"
      scoredVendors = scoreVendors(vendors, latitude, longitude)
      scoredVendors = scoredVendors.filter (a) -> return a.score > 0
      scoredVendors.sort (a,b) -> return b.score - a.score
      topN = scoredVendors.slice(0, n)
      for scoredVendor in topN
        msgVendorInfo msg, scoredVendor, city

