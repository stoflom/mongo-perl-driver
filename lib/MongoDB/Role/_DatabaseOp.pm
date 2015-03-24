#
#  Copyright 2014 MongoDB, Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

package MongoDB::Role::_DatabaseOp;

# MongoDB interface for database operations

use version;
our $VERSION = 'v0.999.998.3'; # TRIAL

use MongoDB::BSON;
use MongoDB::Error;
use MongoDB::_Protocol;
use Moose::Role;
use namespace::clean -except => 'meta';

requires 'execute';

# Sends a BSON query string, then read, parse and validate the reply.
# Throws various errors if the results indicate a problem.  Returns
# a "result" structure generated by MongoDB::_Protocol, but with
# the 'docs' field replaced with inflated documents.

sub _query_and_receive {
    my ( $self, $link, $op_bson, $request_id, $bson_codec ) = @_;

    $link->write($op_bson);
    my $result = MongoDB::_Protocol::parse_reply( $link->read, $request_id );

    # XXX should address be added to result here?

    if ( $result->{flags}{cursor_not_found} ) {
        MongoDB::CursorNotFoundError->throw("cursor not found");
    }

    my $doc_bson = $result->{docs};

    my @documents;

    # XXX eventually, BSON needs an API to do this efficiently for us without a
    # loop here.  Alternatively, BSON strings could be returned as objects that
    # inflate lazily

    for ( 1 .. $result->{number_returned} ) {
        my $len = unpack( MongoDB::_Protocol::P_INT32(), substr( $doc_bson, 0, 4 ) );
        if ( $len > length($doc_bson) ) {
            MongoDB::ProtocolError->throw("document in response was truncated");
        }
        push @documents,
          MongoDB::BSON::decode_bson( substr( $doc_bson, 0, $len, '' ), $bson_codec );
    }

    if ( @documents != $result->{number_returned} ) {
        MongoDB::ProtocolError->throw("unexpected number of documents");
    }

    if ( length($doc_bson) > 0 ) {
        MongoDB::ProtocolError->throw("unexpected extra data in response");
    }

    $result->{docs} = \@documents;

    if ( $result->{flags}{query_failure} ) {
        # pretend the query was a command and assert it here
        MongoDB::CommandResult->new(
            result  => $result->{docs}[0],
            address => $link->address
        )->assert;
    }

    return $result;
}

1;