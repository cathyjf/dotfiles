require 'etc'

# Determines the username associated with Cathy's UID.
# This is expected to be "Cathy".
Facter.add('cathy_username') do
    setcode do
        cathy_uid = Facter.value('cathy_uid')
        raise 'cathy_username failed because cathy_uid failed' if cathy_uid.nil?
        Etc.getpwuid(cathy_uid).name
    end
end