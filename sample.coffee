############################################################################
#     Copyright (C) 2014-2015 by Vaughn Iverson
#     meteor-file-sample-app is free software released under the MIT/X11 license.
#     See included LICENSE file for details.
############################################################################

# Both client and server

# Default collection name is 'fs'
myData = FileCollection({
   resumable: true,     # Enable the resumable.js compatible chunked file upload interface
   resumableIndexName: 'test',  # Don't use the default MongoDB index name, which is 94 chars long
   http: [ { method: 'get', path: '/md5/:md5', lookup: (params, query) -> return { md5: params.md5 }}]}
   # Define a GET API that uses the md5 sum id files
)

############################################################
# Client-only code
############################################################

if Meteor.isClient

   # This assigns a file drop zone to the "file table"
   # once DOM is ready so jQuery can see it
   Template.collTest.onRendered ->
     myData.resumable.assignDrop $('.fileDrop')
     return

   Meteor.startup () ->

      ################################
      # Setup resumable.js in the UI

      # When a file is added
      myData.resumable.on 'fileAdded', (file) ->
         # Keep track of its progress reactivaly in a session variable
         Session.set file.uniqueIdentifier, 0
         # Create a new file in the file collection to upload to
         myData.insert({
               _id: file.uniqueIdentifier    # This is the ID resumable will use
               filename: file.fileName
               contentType: file.file.type
            },
            (err, _id) ->
               if err
                  console.warn "File creation failed!", err
                  return
               # Once the file exists on the server, start uploading
               myData.resumable.upload()
         )

      # Update the upload progress session variable
      myData.resumable.on 'fileProgress', (file) ->
         Session.set file.uniqueIdentifier, Math.floor(100*file.progress())

      # Finish the upload progress in the session variable
      myData.resumable.on 'fileSuccess', (file) ->
         Session.set file.uniqueIdentifier, undefined

      # More robust error handling needed!
      myData.resumable.on 'fileError', (file) ->
         console.warn "Error uploading", file.uniqueIdentifier
         Session.set file.uniqueIdentifier, undefined

   # Set up an autorun to keep the X-Auth-Token cookie up-to-date and
   # to update the subscription when the userId changes.
   Tracker.autorun () ->
      userId = Meteor.userId()
      Meteor.subscribe 'allData', userId
      $.cookie 'X-Auth-Token', Accounts._storedLoginToken()

   #####################
   # UI template helpers

   shorten = (name, w = 16) ->
      w += w % 4
      w = (w-4)/2
      if name.length > 2*w
         name[0..w] + '…' + name[-w-1..-1]
      else
         name

   truncateId = (id, length = 6) ->
      if id
         if typeof id is 'object'
            id = "#{id.valueOf()}"
         "#{id.substr(0,6)}…"
      else
         ""

   Template.registerHelper "truncateId", truncateId

   Template.collTest.events
      # Wire up the event to remove a file by clicking the `X`
      'click .del-file': (e, t) ->
         # Just the remove method does it all
         myData.remove {_id: this._id}

      'click #treeButton': (e, t) ->
         console.log "Make Tree"
         Meteor.call 'makeTree', (err, res) ->
          console.log "Tree made! #{res.hash} #{res.size}"

      'click #commitButton': (e, t) ->
        console.log "Make Commit"
        Meteor.call 'makeCommit'

      'click #tagButton': (e, t) ->
        console.log "Make Tag"
        Meteor.call 'makeTag'

   Template.collTest.helpers

      dataEntries: () ->
         # Reactively populate the table
         myData.find({})

      shortFilename: (w = 16) ->
         if this.filename?.length
            shorten this.filename, w
         else
            "(no filename)"

      owner: () ->
         this.metadata?._auth?.owner

      id: () ->
         "#{this._id}"

      link: () ->
         myData.baseURL + "/md5/" + this.md5

      uploadStatus: () ->
         percent = Session.get "#{this._id}"
         unless percent?
            "Processing..."
         else
            "Uploading..."

      formattedLength: () ->
         numeral(this.length).format('0.0b')

      uploadProgress: () ->
         percent = Session.get "#{this._id}"

      isImage: () ->
         types =
            'image/jpeg': true
            'image/png': true
            'image/gif': true
            'image/tiff': true
         types[this.contentType]?

      loginToken: () ->
         Meteor.userId()
         Accounts._storedLoginToken()

      userId: () ->
         Meteor.userId()

############################################################
# Server-only code
############################################################

if Meteor.isServer

   Meteor.startup () ->

      # Only publish files owned by this userId, and ignore temp file chunks used by resumable
      Meteor.publish 'allData', (clientUserId) ->

         # This prevents a race condition on the client between Meteor.userId() and subscriptions to this publish
         # See: https://stackoverflow.com/questions/24445404/how-to-prevent-a-client-reactive-race-between-meteor-userid-and-a-subscription/24460877#24460877
         if this.userId is clientUserId
            return myData.find
              'metadata._Resumable':
                $exists: false
              $or: [{ 'metadata._auth.owner': this.userId } , { 'metadata._auth.owners': $in: [ this.userId ] } ]
         else
            return []

      # Don't allow users to modify the user docs
      Meteor.users.deny({update: () -> true })

      # Allow rules for security. Without these, no writes would be allowed by default
      myData.allow
         insert: (userId, file) ->
            # Assign the proper owner when a file is created
            file.metadata = file.metadata ? {}
            file.metadata._auth =
               owner: userId
            true
         remove: (userId, file) ->
            # Only owners can delete
            if file.metadata?._auth?.owner and userId isnt file.metadata._auth.owner
               return false
            true
         read: (userId, file) ->
            # Only owners can GET file data
            if file.metadata?._auth?.owner and userId isnt file.metadata._auth.owner
               return false
            true
         write: (userId, file, fields) -> # This is for the HTTP REST interfaces PUT/POST
            # All client file metadata updates are denied, implement Methods for that...
            # Only owners can upload a file
            if file.metadata?._auth?.owner and userId isnt file.metadata._auth.owner
               return false
            true

      objPath = (hash) ->
         return "objects/#{hash.slice(0,2)}/#{hash.slice(2)}"

      addedFile = (file) ->
        # Check if this blob exists
        myData.findOneStream({ md5: file.md5 }).pipe(
          myData.gbs.blobWriter { type: 'blob', size: file.length, noOutput: true }, Meteor.bindEnvironment (err, data) ->
            console.dir data
            unless myData.findOne { filename: objPath data.hash }
              bw = myData.gbs.blobWriter
                  type: 'blob'
                  size: file.length
                , (err, obj) -> console.dir obj
              os = myData.upsertStream
                filename: objPath data.hash
                aliases: [ file.filename ]
                metadata:
                  _auth:
                    owners: [ file.metadata._auth.owner ]
                  _Git:
                    type: 'blob'
                    size: file.length
                    md5: file.md5
                , (err, f) ->
                    console.dir f, { depth: null }
                    console.log "#{data.hash} written! as #{f._id}", err
                    myData.update
                        _id: file._id
                        md5: file.md5
                      ,
                        $set:
                          "metadata.sha1": data.hash
                    console.dir myData.findOne file._id
              myData.findOneStream({ md5: file.md5 })?.pipe(bw)?.pipe(os)
            else
              myData.update
                  filename: data.hash
                  "metadata._Git":
                    $exists: true
                ,
                  $addToSet:
                    aliases: file.filename
                    "metadata._auth.owners": file.metadata._auth.owner
              myData.update
                  _id: file._id
                  md5: file.md5
                ,
                  $set:
                    "metadata.sha1": data.hash
        )

      changedFile = (oldFile, newFile) ->
         if oldFile.md5 isnt newFile.md5
            addedFileJob newFile

      fileObserve = myData.find(
         md5:
            $ne: 'd41d8cd98f00b204e9800998ecf8427e'  # md5 sum for zero length file
         'metadata._Resumable':
            $exists: false
         'metadata._Git':
            $exists: false
      ).observe(
        added: addedFile
        changed: changedFile
      )

      Meteor.methods
        writeHEAD: (ref) ->
          query =
            filename: 'HEAD'
            "metadata._Git.type": 'HEAD'
          head = myData.findOne query
          query =
            filename: 'HEAD'
            metadata:
              _Git:
                type: 'HEAD'
                ref: ref
          if head
            query._id = head._id

          console.log "Writing Query!", query
          os = myData.upsertStream query, (err, f) -> console.dir f
          os.end "#{ref}\n"

        makeTree: () ->
          console.log "Making a tree!"
          tree = myData.find(
             md5:
                $ne: 'd41d8cd98f00b204e9800998ecf8427e'  # md5 sum for zero length file
             'metadata._Resumable':
                $exists: false
             'metadata._Git':
                $exists: false
          ).map (f) -> { name: f.filename, mode: myData.gbs.gitModes.file, hash: f.metadata.sha1 }
          console.dir tree
          data = Async.wrap(myData.gbs.treeWriter) tree, { arrayTree: true, noOutput: true }
          console.log "tree should be: #{data.hash}, #{data.size}"
          unless myData.findOne { filename: objPath data.hash }
            os = myData.upsertStream
                filename: objPath data.hash
                metadata:
                  _Git:
                    type: 'tree'
                    size: data.size
                    tree: data.tree
              , (err, f) ->
                  console.dir f, { depth: null }
                  console.log "#{data.hash} written! as #{f._id}", err
            myData.gbs.treeWriter(tree).pipe(os)
          console.log "Returning #{data.hash}"
          return data

        makeCommit: () ->
          console.dir Meteor.user()
          console.log "Making a commit!"
          console.log "Calling make tree"
          tree = Meteor.call 'makeTree'
          console.dir tree
          head = myData.findOne
            filename: 'HEAD'
            "metadata._Git.type": 'HEAD'
          commit =
            author:
              name: "Vaughn Iverson"
              email: "vsi@uw.edu"
            tree: tree.hash
            message: "Test commit\n"
          if head
            console.log "Found HEAD!", head
            commit.parent = head.metadata._Git.ref
          else
            console.log "No HEAD!"
          data = Async.wrap(myData.gbs.commitWriter) commit, { noOutput: true }
          console.log "commit should be: #{data.hash}, #{data.size}"
          unless myData.findOne { filename: objPath data.hash }
            os = myData.upsertStream
                filename: objPath data.hash
                metadata:
                  _Git:
                    type: 'commit'
                    size: data.size
                    commit: data.commit
              , (err, f) ->
                  console.dir f.metadata._Git.commit, { depth: null }
                  console.log "#{data.hash} written! as #{f._id}", err
                  Meteor.call 'writeHEAD', data.hash
            myData.gbs.commitWriter(commit).pipe(os)
          console.log "Returning #{data.hash}"
          return data

        makeTag: () ->
          console.dir Meteor.user()
          console.log "Making a tag!"
