# Returns the GID of the specified group, if that group exists.
# Otherwise, returns the GID of the fallback group.
Puppet::Functions.create_function(:get_gid) do
    dispatch :impl do
        required_param 'String', :groupname
        optional_param 'String', :fallback_groupname
        return_type 'Numeric'
    end

    def impl(groupname, fallback_groupname = 'everyone')
        Etc.getgrnam(groupname).gid
    rescue ArgumentError
        Etc.getgrnam(fallback_groupname).gid
    end
  end