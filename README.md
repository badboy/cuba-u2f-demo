# U2F Demo based on Cuba.rb

A [Cuba.rb][cuba] based demo application with user authentication using the [U2F protocol][u2f-overview], as implemented by [ruby-u2f][u2f.rb].

A complete blog post about this demo and U2F is available on my blog: [U2F demo][blogpost].


## Usage

Install all required gems (in case you have [dep][] installed):

    dep install

or install them manually:

    gem install $(awk '{print $1}' .gems | tr '\n' ' ')

Install the Chrome extension: [FIDO U2F (Universal 2nd Factor) extension][chrome-addon]

Fire up a Redis server:

    redis-server &

and then start the Rack server:

    rackup config.ru

Go to <http://localhost:9292>.

You can create new users, login, add keys and are prompted for these keys when authenticating again.

## License

Yes, even this little thing has a license. It's available under the conditions of the MIT license, see [LICENSE](LICENSE) for the full text.

[cuba]: https://github.com/soveran/cuba
[u2f.rb]: https://github.com/castle/ruby-u2f
[blogpost]: https://fnordig.de/...
[u2f-overview]: http://fidoalliance.org/specs/fido-u2f-v1.0-ps-20141009/fido-u2f-overview-ps-20141009.html
[dep]: https://github.com/cyx/dep
[chrome-addon]: https://chrome.google.com/webstore/detail/fido-u2f-universal-2nd-fa/pfboblefjcgdjicmnffhdgionmgcdmne
