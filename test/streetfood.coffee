chai = require 'chai'
sinon = require 'sinon'
chai.use require 'sinon-chai'

expect = chai.expect

describe 'streetfood', ->
  beforeEach ->
    @robot =
      respond: sinon.spy()
      hear: sinon.spy()
      brain: {
      	data: {}
      }

    require('../src/streetfood')(@robot)

  it 'registers a respond listener', ->
    expect(@robot.respond).to.have.been.calledWith(//)
