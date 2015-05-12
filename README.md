## file-collection Sample App

This is a sample application demonstrating the use of the Meteor [file-collection](https://atmospherejs.com/vsivsi/file-collection) package.

Note! This version of the sample app uses Meteor 1.1.0.2 and file-collection 1.1.0

This demo app uses file-collection's built-in support for [Resumable.js](http://www.resumablejs.com/) to allow drag and drop uploading of files. Beyond that, it presents a simple image management grid with basic metadata, user acounts with file ownership, previews of images with click to load, and the ability to download or delete files.

Just run `meteor` in this directory and then once the app server is running, point your browser at `http://localhost:3000/`.

For a more advanced example that uses the `job-collection` package to automatically create and use thumbnails for uploaded images, see: https://github.com/vsivsi/meteor-file-job-sample-app
