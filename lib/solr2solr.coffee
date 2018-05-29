path = require 'path'
solr = require 'solr'
_ =    require 'underscore'
extend = require('util')._extend;

class SolrToSolr

  go: (@config) ->
    @sourceClient = solr.createClient(@config.from)
    @destClient   = solr.createClient(@config.to)

    @config.start = @config.start || 0
    @config.params = @config.params || {}
    @config.params = @config.params || {}

    @nextBatch(@config.start, @config.params)

  nextBatch: (start, params) ->
    
    console.log "Querying starting at #{start}"
    
    newParams = extend(params, {rows: @config.rows, start:start});

    console.log(newParams)

    @sourceClient.query @config.query, newParams, (err, response) =>
      return console.log "Some kind of solr query error #{err}" if err?
      responseObj = JSON.parse response

      newDocs = @prepareDocuments(responseObj.response.docs, start)
      @writeDocuments newDocs, =>
        start += @config.rows
        if responseObj.response.numFound > start
          @nextBatch(start, newParams)
        else
          @destClient.commit()

  prepareDocuments: (docs, start) =>
    for doc in docs
      newDoc = {} 
      if @config.clone
        for cloneField of doc
          newDoc[cloneField] = doc[cloneField]
      else
        for copyField in @config.copy
          newDoc[copyField] = doc[copyField] if doc[copyField]?
      for transform in @config.transform
        newDoc[transform.destination] = doc[transform.source] if doc[transform.source]?
      for fab in @config.fabricate
        vals = fab.fabricate(newDoc, start)
        newDoc[fab.name] = vals if vals?
      for exclude in @config.exclude
        delete newDoc[exclude]
        newDoc['latlng'] = doc['Latitude, Longitude']

      start++
      newDoc

  writeDocuments: (documents, done) ->
    docs = []
    docs.push documents
    if @config.duplicate.enabled
      for doc in documents
        console.log documents
        for num in [0..@config.duplicate.numberOfTimes]
          newDoc = _.extend({}, doc)
          newDoc[@config.duplicate.idField] = "#{doc[@config.duplicate.idField]}-#{num}"
          docs.push newDoc

    @destClient.add _.flatten(docs), (err) =>
      console.log err if err
      @destClient.commit()
      done()

exports.go = (config) ->
  (new SolrToSolr()).go(config)
