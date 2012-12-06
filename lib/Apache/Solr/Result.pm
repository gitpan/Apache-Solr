# Copyrights 2012 by [Mark Overmeer].
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.00.
package Apache::Solr::Result;
use vars '$VERSION';
$VERSION = '0.92';


use warnings;
use strict;

use Log::Report    qw(solr);
use Time::HiRes    qw(time);
use Scalar::Util   qw(weaken);

use Apache::Solr::Document ();

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Quotekeys = 0;


use overload
    '""' => 'endpoint'
  , bool => 'success';


sub new(@) { my $c = shift; (bless {}, $c)->init({@_}) }
sub init($)
{   my ($self, $args) = @_;
    $self->{ASR_params}   = $args->{params}   or panic;
    $self->{ASR_endpoint} = $args->{endpoint} or panic;

    $self->{ASR_start}    = time;
    $self->request($args->{request});
    $self->response($args->{response});

    $self->{ASR_pages} = [$self];
    weaken $self->{ASR_pages}[0];            # no reference loop!
    $self;
}

# replace the pageset with a shared set.
sub _pageset($) { $_[0]->{ASR_pages} = $_[1] }

#---------------

sub start()    {shift->{ASR_start}}
sub endpoint() {shift->{ASR_endpoint}}
sub params()   {@{shift->{ASR_params}}}

sub request(;$) 
{   my $self = shift;
    @_ && $_[0] or return $self->{ASR_request};
    $self->{ASR_req_out} = time;
    $self->{ASR_request} = shift;
}

sub response(;$) 
{   my $self = shift;
    @_ && $_[0] or return $self->{ASR_response};
    $self->{ASR_resp_in}  = time;
    $self->{ASR_response} = shift;
}

sub decoded(;$) 
{   my $self = shift;
    @_ or return $self->{ASR_decoded};
    $self->{ASR_dec_done} = time;
    $self->{ASR_decoded}  = shift;
}

sub elapse()
{   my $self = shift;
    my $done = $self->{ASR_dec_done} or return;
    $done = $self->{ASR_start};
}


sub success() { my $s = shift; $s->{ASR_success} ||= $s->solrStatus==0 }


sub solrStatus()
{   my $dec  = shift->decoded or return 500;
    $dec->{responseHeader}{status};
}

sub solrQTime()
{   my $dec   = shift->decoded or return;
    my $qtime = $dec->{responseHeader}{QTime};
    defined $qtime ? $qtime/1000 : undef;
}

sub solrError()
{   my $dec  = shift->decoded or return;
    my $err  = $dec->{error};
    $err ? $err->{msg} : undef;
}

#--------------------------

sub terms($;$)
{   my ($self, $field) = (shift, shift);
    return $self->{ASR_terms}{$field} = shift if @_;

    my $r = $self->{ASR_terms}{$field}
        or error __x"no search for terms on field {field} requested"
            , field => $field;

    $r;
}


sub nrSelected()
{   my $results = shift->decoded->{result}
        or panic "there are no results (yet)";

    $results->{numFound};
}


sub selected($;$)
{   my ($self, $rank, $client) = @_;
    my $dec    = $self->decoded;
    my $result = $dec->{result}
        or panic "there are no results (yet)";

    # in this page?
    if($rank <= $result->{start})
    {   my $docs = $result->{doc};
        $docs    = [$docs] if ref $docs eq 'HASH';
        if($rank - $result->{start} < @$docs)
        {   my $doc = $docs->[$rank - $result->{start}];
            return Apache::Solr::Document->fromResult($doc, $rank);
        }
    }

    $rank < $result->{numFound}       # outside answer range
        or return ();
 
    my $pagenr  = $self->selectedPageNr($rank);
    my $page    = $self->selectedPage($pagenr)
               || $self->selectedPageLoad($pagenr, $client);
    $page->selected($rank);
}


sub highlighted($)
{   my ($self, $doc) = @_;
    my $rank   = $doc->rank;
    my $pagenr = $self->selectedPageNr($rank);
    my $hl     = $self->selectedPage($pagenr)->decoded->{highlighting}
        or error __x"there is no highlighting information in the result";
    Apache::Solr::Document->fromResult($hl->{$doc->uniqueId}, $rank);
}

#--------------------------

sub _to_msec($) { sprintf "%.1f", $_[0] * 1000 }

sub showTimings(;$)
{   my ($self, $fh) = @_;
    $fh ||= select;
    my $req     = $self->request;
    my $to      = $req ? $req->uri : '(not set yet)';
    my $start   = localtime $self->{ASR_start};

    $fh->print("endpoint: $to\nstart:    $start\n");

    if($req)
    {   my $reqsize = length($req->as_string);
        my $reqcons = _to_msec($self->{ASR_req_out} - $self->{ASR_start});
        $fh->print("request:  constructed $reqsize bytes in $reqcons ms\n");
    }

    if(my $resp = $self->response)
    {   my $respsize = length($resp->as_string);
        my $respcons = _to_msec($self->{ASR_resp_in} - $self->{ASR_req_out});
        $fh->print("response: received $respsize bytes after $respcons ms\n");
        my $ct       = $resp->content_type;
        my $status   = $resp->status_line;
        $fh->print("          $ct, $status\n");
    }

    if(my $dec = $self->decoded)
    {   my $decoder = _to_msec($self->{ASR_dec_done} - $self->{ASR_resp_in});
        $fh->print("decoding: completed in $decoder ms\n");
        if(defined(my $qt = $self->solrQTime))
        {   $fh->print("          solr processing took "._to_msec($qt)." ms\n");
        }
        if(my $error = $self->solrError)
        {   $fh->print("          solr reported error: '$error'\n");
        }
        my $total   = _to_msec($self->{ASR_dec_done} - $self->{ASR_start});
        $fh->print("elapse:   $total ms total\n");
    }
}


sub selectedPageNr($) { my $pz = shift->selectedPageSize; int(shift() / $pz) }
sub selectPages()     { @{shift->{ASR_pages}} }
sub selectedPage($)   { my $pages = shift->{ASR_pages}; $pages->[shift()] }
sub selectedPageSize()
{   my $result = shift->selectedPage(0)->decoded->{result};
    my $docs   = $result ? $result->{doc} : undef;
    ref $docs eq 'HASH'  ? 1 : ref $docs eq 'ARRAY' ? scalar @$docs : 50;
}


sub selectedPageLoad($;$)
{   my ($self, $pagenr, $client) = @_;
    $client
        or error __x"cannot autoload page {nr}, no client provided"
             , nr => $pagenr;

    my $pz     = $self->selectedPageSize;
    my @params = $self->replaceParams
      ( {start => $pagenr * $pz, rows => $pz}, $self->params);

    my $page   = $client->select(@params);
    $page->_pageset($self->{ASR_pages});

    # put new page in shared table of pages
    # no weaken here?  only the first request is captured in the main program.
    $self->{ASR_pages}[$pagenr] = $page;
}


sub replaceParams($@)
{   my ($self, $new) = (shift, shift);
    my @out;
    while(@_)
    {    my ($k, $v) = (shift, shift);
         $v = delete $new->{$k} if $new->{$k};
         push @out, $k => $v;
    }
    (@out, %$new);
}

1;
