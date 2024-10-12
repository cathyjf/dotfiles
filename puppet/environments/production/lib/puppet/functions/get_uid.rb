# Returns the UID of the specified user, if that user exists.
# Otherwise, returns Undef.
Puppet::Functions.create_function(:get_uid) do
    dispatch :impl do
        required_param 'String', :username
        return_type 'Variant[Numeric, Undef]'
    end

    def impl(username)
        Etc.getpwnam(username).uid
    rescue ArgumentError
        nil
    end
  end