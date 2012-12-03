# Copyrights 2012 by [Mark Overmeer].
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 2.00.
package Apache::Solr::Tables;
use vars '$VERSION';
$VERSION = '0.90';

use base 'Exporter';

our @EXPORT = qw/%boolparams %introduced %deprecated/;

our %boolparams = map +($_ => 1), qw/
echoHandler
facet
facet.date.hardend
facet.missing
facet.range.hardend
facet.zeros
group
group.facet
group.main
group.ngroups
group.truncate
hl
hl.mergeContiguous
hl.requireFieldMatch
hl.useFastVectorHighlighter
indent
mlt
omitHeader
stats
terms.lower.incl
terms.raw
terms.upper.incl

 /;

our %introduced = qw/
debug			4.0
debug.explain.structured	3.2
facet.date		1.3
facet.date.include	3.1
facet.enum.cache.minDf	1.2
facet.method		1.4
facet.mincount		1.2
facet.offset		1.2
facet.pivot		4.0
facet.prefix		1.2
facet.range		3.1
facet.range.gap		3.6
hl.alternateField	1.3
hl.boundaryScanner	3.5
hl.bs.chars		3.5
hl.bs.country		3.5
hl.bs.language		3.5
hl.bs.type		3.5
hl.fragListBuilder	3.1
hl.fragmenter		1.3
hl.fragmentsBuilder	3.1
hl.highlightMultiTerm	1.4
hl.maxAlternateFieldLength	1.3
hl.maxAnalyzedChars	1.3
hl.mergeContiguous	1.3
hl.q			3.5
hl.useFastVectorHighlighter	3.1
hl.usePhraseHighlighter	1.3
pageDoc			4.0
pageScore		4.0
qs			1.3
terms.regex		3.2
timeAllowed		1.3
/;

our %deprecated = qw/
 facet.date		3.1
 facet.zeros		1.2
/;

