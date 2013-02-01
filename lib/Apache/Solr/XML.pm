# Copyrights 2012-2013 by [Mark Overmeer].
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.01.
package Apache::Solr::XML;
use vars '$VERSION';
$VERSION = '0.95';

use base 'Apache::Solr';

use warnings;
use strict;

use Log::Report          qw(solr);

use Apache::Solr::Result ();
use XML::LibXML::Simple  ();
use HTTP::Message        ();
use HTTP::Request        ();
use Scalar::Util         qw(blessed);

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Quotekeys = 0;

# See the XML::LibXML::Simple manual page
my @xml_decode_config =
  ( ForceArray   => []
  , ContentKey   => '_'
  , KeyAttr      => []
  );
sub _cleanup_parsed($);


sub init($)
{   my ($self, $args) = @_;
    $args->{format} ||= 'XML';

    $self->SUPER::init($args);

    $self->{ASX_simple} = XML::LibXML::Simple->new(@xml_decode_config);
    $self;
}

#---------------
sub xmlsimple() {shift->{ASX_simple}}

#--------------------------

sub _select($)
{   my ($self, $params) = @_;
    my @params   = @$params;

    # select can be called automatically, more than once.  We do not
    # want to add 'wt' each call.
    my %params   = @params;
    unshift @params, wt => 'xml' unless $params{wt};

    my $endpoint = $self->endpoint('select', params => \@params);
    my $result   = Apache::Solr::Result->new(params => \@params
      , endpoint => $endpoint, core => $self);
    $self->request($endpoint, $result);
    $result;
}

sub _extract($$$)
{   my ($self, $params, $data, $ct) = @_;
    my @params   = (wt => 'xml', @$params);
    my $endpoint = $self->endpoint('update/extract', params => \@params);
    my $result   = Apache::Solr::Result->new(params => \@params
      , endpoint => $endpoint, core => $self);
    $self->request($endpoint, $result, $data, $ct);
    $result;
}

sub _add($$$)
{   my ($self, $docs, $attrs, $params) = @_;
    $attrs  ||= {};
    $params ||= {};

    my $doc   = XML::LibXML::Document->new('1.0', 'UTF-8');
    my $add   = $doc->createElement('add');
    $add->setAttribute($_ => $attrs->{$_}) for sort keys %$attrs;

    $add->addChild($self->_doc2xml($doc, $_))
        for @$docs;

    $doc->setDocumentElement($add);

    my @params   = (wt => 'xml', %$params);
    my $endpoint = $self->endpoint('update', params => \@params);
    my $result   = Apache::Solr::Result->new(params => \@params
      , endpoint => $endpoint, core => $self);
    $self->request($endpoint, $result, $doc);
    $result;
}

sub _doc2xml($$$)
{   my ($self, $doc, $this) = @_;

    my $node  = $doc->createElement('doc');
    my $boost = $this->boost || 1.0;
    $node->setAttribute(boost => $boost) if $boost != 1.0;

    foreach my $field ($this->fields)
    {   my $fnode = $doc->createElement('field');
        $fnode->setAttribute(name => $field->{name});
        my $boost = $field->{boost} || 1.0;
        $fnode->setAttribute(boost => $boost) if $boost != 1.0;
        $fnode->appendText($field->{content});
        $node->addChild($fnode);
    }
    $node;
}

sub _commit($)   { my ($s, $attr) = @_; $s->simpleUpdate(commit   => $attr) }
sub _optimize($) { my ($s, $attr) = @_; $s->simpleUpdate(optimize => $attr) }
sub _delete($$)  { my $self = shift; $self->simpleUpdate(delete   => @_) }
sub _rollback()  { shift->simpleUpdate('rollback') }

sub _terms($)
{   my ($self, $terms) = @_;

    my @params   = (wt => 'xml', @$terms);
    my $endpoint = $self->endpoint('terms', params => \@params);
    my $result   = Apache::Solr::Result->new(params => \@params
      , endpoint => $endpoint, core => $self);

    $self->request($endpoint, $result);

    my $table = $result->decoded->{terms} || {};
    while(my ($field, $terms) = each %$table)
    {   my @terms = map [ $_ => $terms->{$_} ]
          , sort {$terms->{$b} <=> $terms->{$a}}
              keys %$terms;
        $result->terms($field => \@terms);
    }

    $result;
}

#--------------------------

sub request($$;$$)
{   my ($self, $url, $result, $body, $body_ct) = @_;

    if(blessed $body && $body->isa('XML::LibXML::Document'))
    {   $body_ct ||= 'text/xml; charset=utf-8';
        $body      = \$body->toString;
    }

    my $resp = $self->SUPER::request($url, $result, $body, $body_ct);
    my $ct   = $resp->content_type;
#warn $resp->as_string;
    $ct =~ m/xml/i or return $result;

    my $dec = $self->xmlsimple
       ->XMLin($resp->decoded_content || $resp->content);

#warn Dumper $dec;
    $result->decoded(_cleanup_parsed $dec);
    $result;
}

sub _cleanup_parsed($)
{   my $data = shift;

    if(!ref $data) { return $data }
    elsif(ref $data eq 'HASH')   
    {   my %d = %$data;   # start with shallow copy

        # Hash
        if(my $lst = delete $d{lst})
        {   foreach (ref $lst eq 'ARRAY' ? @$lst : $lst)
            {   my $name  = delete $_->{name};
                $d{$name} = $_;
            }
        }

        # Array
        if(my $arr = delete $d{arr})
        {   foreach (ref $arr eq 'ARRAY' ? @$arr : $arr)
            {   my $name   = delete $_->{name};
                my ($type, $values) = %$_;
                $values = [$values] if ref $values ne 'ARRAY';
                $d{$name} = $values;
            }
        }

        foreach my $type (qw/int long str float bool/)
        {   my $items = delete $d{$type} or next;
            foreach (ref $items eq 'ARRAY' ? @$items : $items)
            {   my ($name, $value)
                    = ref $_ eq 'HASH' ? ($_->{name}, $_->{_}) : ('', $_);
                $value = $value eq 'true' || $_->{_} eq 1
                    if $type eq 'bool';
                $d{$name} = $value;
            }
        }

        foreach my $key (keys %d)
        {   $d{$key} = _cleanup_parsed($d{$key}) if ref $d{$key};
        }
        return \%d;
    }
    elsif(ref $data eq 'ARRAY')
    {   return [ map _cleanup_parsed($_), @$data ];
    }
    else {panic $data}
}


sub simpleUpdate($$;$)
{   my ($self, $command, $attrs, $content) = @_;
    $attrs     ||= {};
    my @params   = (wt => 'xml', commit => delete $attrs->{commit});
    my $endpoint = $self->endpoint('update', params => \@params);
    my $result   = Apache::Solr::Result->new(params => \@params
      , endpoint => $endpoint, core => $self);

    my $doc      = $self->simpleDocument($command, $attrs, $content);
    $self->request($endpoint, $result, $doc);
    $result;
}


sub simpleDocument($;$$)
{   my ($self, $command, $attrs, $content) = @_;
    my $doc  = XML::LibXML::Document->new('1.0', 'UTF-8');
    my $top  = $doc->createElement($command);
    $doc->setDocumentElement($top);

    $attrs ||= {};
    $top->setAttribute($_ => $attrs->{$_}) for sort keys %$attrs;

    if(!defined $content) {}
    elsif(ref $content eq 'HASH' || ref $content eq 'ARRAY')
    {   my @c = ref $content eq 'HASH' ? %$content : @$content;
        while(@c)
        {   my ($name, $values) = (shift @c, shift @c);
            foreach my $value (ref $values eq 'ARRAY' ? @$values : $values)
            {   my $node = $doc->createElement($name);
                $node->appendText($value);
                $top->addChild($node);
            }
        }
    }
    else
    {   $top->appendText($content);
    }
    $doc;
}

1;
