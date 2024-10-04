# Returns the username associated with the specified UID.
Puppet::Functions.create_function(:get_username) do
    dispatch :impl do
        required_param 'Numeric', :uid
        return_type 'String'
    end

    def impl(uid)
        Etc.getpwuid(uid).name
    end
end