#!/usr/bin/perl

use warnings;
use strict;

use lib 'lib';
use Test::More;

my $server;

use Data::Dumper;
$Data::Dumper::Indent = 1;
$Data::Dumper::Quotekeys = 0;

BEGIN {
    $server = $ENV{SOLR_TEST_SERVER}
        or plan skip_all => "no SOLR_TEST_SERVER provided";

    plan tests => 36;
}

require_ok('Apache::Solr');
require_ok('Apache::Solr::Document');

my $format = $0 =~ m/xml/ ? 'xml' : 'json';
my $FORMAT = uc $format;

my $solr = Apache::Solr->new(format => $FORMAT, server => $server);
ok(defined $solr, "instantiated client in $format");

isa_ok($solr, 'Apache::Solr::'.$FORMAT);

my $result = eval { $solr->commit };
ok(!$@, 'try commit:'.$@);

isa_ok($result, 'Apache::Solr::Result');
is($result->endpoint, "$result");

$result->showTimings(\*STDERR);

ok($result->success, 'successful');

### test $solr->addDocument()
my $d1a = Apache::Solr::Document->new
  ( fields => [ id => 1, subject => '1 2 3', content => "<html>tic tac"
              , content_type => 'text/html' ]
  );

my $d1b = Apache::Solr::Document->new
  ( fields => [ id => 2, content => "<body>tac too"
              , content_type => 'text/html' ]
  , boost  => '5'
  );

$solr->addDocument([$d1a, $d1b], commit => 1, overwrite => 1);

### test $solr->terms()

my $t1 = $solr->queryTerms(fl => 'id', limit => 20);
isa_ok($t1, 'Apache::Solr::Result');

my $r1 = $t1->terms('id');
#warn Dumper $r1;

ok(defined $r1, 'lookup search results for "id"');
isa_ok($r1, 'ARRAY');
cmp_ok(scalar @$r1, '==', 2, 'both documents have an id');
isa_ok($r1->[0], 'ARRAY', 'is array of arrays');
cmp_ok(scalar @{$r1->[0]}, '==', 2, 'each size 2');
cmp_ok(scalar @{$r1->[1]}, '==', 2, 'each size 2');

### test $solr->select with one result

my $t2 = $solr->select(q => 'text:tic', hl => {fl => 'content'});
#warn Dumper $t2->decoded;
isa_ok($t2, 'Apache::Solr::Result');
ok($t2, 'select was successfull');
is($t2->endpoint, "$server/select?wt=$format&q=text%3Atic&hl=true&hl.fl=content");

cmp_ok($t2->nrSelected, '==', 1);

my $d2 = $t2->selected(0);
#warn Dumper $d2;
isa_ok($d2, 'HASH', 'got 1 answer');
ok($d2->{doc}, 'got 1 document');
ok($d2->{hl}, 'got 1 hightlights');

### test $solr->select with two results

my $t3 = $solr->select(q => 'text:tac', rows => 1, hl => {fl => 'content'});
#warn Dumper $t3->decoded;
isa_ok($t3, 'Apache::Solr::Result');
ok($t3, 'select was successfull');
is($t3->endpoint, "$server/select?wt=$format&q=text%3Atac&rows=1&hl=true&hl.fl=content");

cmp_ok($t3->nrSelected, '==', 2, '2 items selected');

cmp_ok($t3->selectedPageSize, '==', 1, 'page size 1');
cmp_ok($t3->selectedPageNr(0), '==', 0, 'item 0 on page 0');
cmp_ok($t3->selectedPageNr(1), '==', 1, 'item 1 on page 1');

my $d3a = $t3->selected(0);
#warn Dumper $d3a;
isa_ok($d3a, 'HASH', 'got 1 answer');
ok($d3a->{doc}, 'got 1 document');
ok($d3a->{hl}, 'got 1 hightlights');

my $d3b = $t3->selected(1, $solr);
#warn Dumper $d3b;
isa_ok($d3b, 'HASH', 'got 2 answer');
ok($d3b->{doc}, 'got 2 document');
ok($d3b->{hl}, 'got 2 hightlights');

my $d3c =  $t3->selected(0);
cmp_ok($d3a->{doc}, 'eq', $d3c->{doc}, "take again");

