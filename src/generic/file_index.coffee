# A simple class for storing a filesystem index. Assumes that all paths passed
# to it are *absolute* paths.
#
# Can be used as a partial or a full index, although care must be taken if used
# for the former purpose, especially when directories are concerned.
class BrowserFS.FileIndex
  # Constructs a new FileIndex.
  constructor: ->
    # _index is a single-level key,value store that maps *directory* paths to
    # DirInodes. File information is only contained in DirInodes themselves.
    @_index = {}

  # Split into a (directory path, item name) pair
  _split_path: (path) ->
    dirpath = BrowserFS.node.path.dirname path
    itemname = path.substr(dirpath.length + if dirpath is "/" then 0 else 1)
    return [dirpath, itemname]

  # Adds the given absolute path to the index if it is not already in the index.
  # Creates any needed parent directories.
  # @param [String] path The path to add to the index.
  # @param [BrowserFS.FileInode | BrowserFS.DirInode] inode The inode for the
  #   path to add.
  # @return [Boolean] 'True' if it was added or already exists, 'false' if there
  #   was an issue adding it (e.g. item in path is a file, item exists but is
  #   different).
  # @todo If adding fails and implicitly creates directories, we do not clean up
  #   the new empty directories.
  addPath: (path, inode) ->
    throw new Error 'Inode must be specified' unless inode?
    throw new Error 'Path must be absolute, got: '+path unless path[0] is '/'

    # Check if it already exists.
    if @_index[path] isnt undefined
      return @_index[path] is inode

    [dirpath, itemname] = @_split_path path

    # Try to add to its parent directory first.
    parent = @_index[dirpath]
    if parent is undefined and path isnt '/'
      # Create parent.
      parent = new BrowserFS.DirInode()
      return false unless @addPath dirpath, parent

    # Add myself to my parent.
    unless path is '/'
      return false unless parent.addItem itemname, inode

    # If I'm a directory, add myself to the index.
    @_index[path] = inode unless inode.isFile()
    return true

  # Removes the given path. Can be a file or a directory.
  # @return [BrowserFS.FileInode | BrowserFS.DirInode | null] The removed item,
  #   or null if it did not exist.
  removePath: (path) ->
    [dirpath, itemname] = @_split_path path

    # Try to remove it from its parent directory first.
    parent = @_index[dirpath]
    if parent is undefined then return null

    # Remove myself from my parent.
    inode = parent.remItem itemname
    return null if inode is null

    # If I'm a directory, remove myself from the index.
    # We assume that the presence of the inode in its parent's inode indicates
    # that it must also be in _index.
    unless inode.isFile() then delete @_index[path]
    return inode

  # Retrieves the directory listing of the given path.
  # @return [String[]] An array of files in the given path, or 'null' if it does
  #   not exist.
  ls: (path) ->
    item = @_index[path]
    return null if item is undefined
    return item.getListing()

  # Returns the inode of the given item.
  # @param [String] path
  # @return [BrowserFS.FileInode | BrowserFS.DirInode | null] Returns null if
  #   the item does not exist.
  getInode: (path) ->
    [dirpath, itemname] = @_split_path path

    # Retrieve from its parent directory.
    parent = @_index[dirpath]
    if parent is undefined then return null
    # Root case
    if dirpath is path then return parent
    return parent.getItem itemname

# Static method for constructing indices from a JSON listing.
# @param [Object] listing Directory listing generated by tools/XHRIndexer.coffee
# @return [BrowserFS.FileIndex] A new FileIndex object.
BrowserFS.FileIndex.from_listing = (listing) ->
  idx = new BrowserFS.FileIndex()
  # Add a root DirNode.
  rootInode = new BrowserFS.DirInode()
  idx._index['/'] = rootInode
  queue = [['', listing, rootInode]]
  while queue.length > 0
    [pwd, tree, parent] = queue.pop()
    for node, children of tree
      name = "#{pwd}/#{node}"
      if children?
        idx._index[name] = inode = new BrowserFS.DirInode()
        queue.push [name, children, inode]
      else
        # This inode doesn't have correct size information, noted with -1.
        idx._index[name] = inode = new BrowserFS.FileInode(BrowserFS.node.fs.Stats.FILE, -1)
      if parent?
        parent._ls[node] = inode
  return idx

# Inode for a file. Just an alias for a BrowserFS.node.fs.Stats object.
BrowserFS.FileInode = BrowserFS.node.fs.Stats

# Inode for a directory. Currently only contains the directory listing.
class BrowserFS.DirInode
  # Constructs an inode for a directory.
  constructor: -> @_ls = {}
  # Is this an inode for a file?
  # @return [Boolean] false
  isFile: -> false
  # Is this an inode for a directory?
  # @return [Boolean] true
  isDirectory: -> true
  # Return a Stats object for this inode.
  # @return [BrowserFS.node.fs.Stats]
  getStats: -> new BrowserFS.node.fs.Stats(BrowserFS.node.fs.Stats.DIRECTORY, 4096)
  # Returns the directory listing for this directory. Paths in the directory are
  # relative to the directory's path.
  # @return [String[]] The directory listing for this directory.
  getListing: -> Object.keys @_ls
  # Returns the inode for the indicated item, or null if it does not exist.
  # @param [String] p Name of item in this directory.
  # @return [BrowserFS.FileInode | BrowserFS.DirInode | null]
  getItem: (p) -> @_ls[p] ? null
  # Add the given item to the directory listing. Note that the given inode is
  # not copied, and will be mutated by the DirInode if it is a DirInode.
  # @param [String] p Item name to add to the directory listing.
  # @param [BrowserFS.FileInode | BrowserFS.DirInode] inode The inode for the
  #   item to add to the directory inode.
  # @return [Boolean] True if it was added, false if it already existed.
  addItem: (p, inode) ->
    return false if p of @_ls
    @_ls[p] = inode
    return true
  # Removes the given item from the directory listing.
  # @param [String] p Name of item to remove from the directory listing.
  # @return [BrowserFS.FileInode | BrowserFS.DirInode | null] Returns the item
  #   removed, or null if the item did not exist.
  remItem: (p) ->
    item = @_ls[p]
    return null if item is undefined
    delete @_ls[p]
    return item
