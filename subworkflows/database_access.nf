// A sentinel keeps process signatures identical for host and image references.
def database_inputs(location, paths, sentinel) {
    if (!(location in ['host', 'container']))
        error 'Database location must be host or container'
    def references = (paths instanceof List ? paths : [paths]).findAll { it }
    return location == 'host' && references
        ? references.collect { file(it, checkIfExists: true) }
        : [sentinel]
}
