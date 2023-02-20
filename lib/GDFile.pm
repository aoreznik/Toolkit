package Table::GDFile;

use strict;
use warnings;
use Dir::Self;
use parent 'Table';
use lib __DIR__;

use Aoddb;
use Atlas;
use File::Basename;
use Data::Dumper;
use Storable 'dclone';
use Encode qw(is_utf8 encode decode decode_utf8);
use List::Util qw(max);
use Mojo::Base -base;

has tablename	=> 'GDFile';
has id_field	=> 'fileid';

our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub load_info {
	my $class = shift;
	my $info = shift;
	my $result;
	my @cols = $class->get_field_dic;
	OUTER_LOAD_INFO: foreach my $key (keys %{$info}) {
		foreach my $arg (@cols) {
			my $dic = $arg; $dic = lc($dic);
			my $cur = $key; $cur = lc($cur);
			if ($cur =~ /info:(\S+)/) {
				$cur = $1;
				}
			next OUTER_LOAD_INFO if $class->is_field_generated($cur);
			if ($cur =~ /meta:(\S+)/) {
				$cur = $1;
				$class->{meta}->{$cur} = $info->{$key};
				next OUTER_LOAD_INFO;
				}
			if ($dic eq $cur) {
				$class->{info}->{$arg} = $info->{$key};
				next OUTER_LOAD_INFO;
				}
			}
		print STDERR "WARNING: field $key was not found in mysql database\n" if $verbose;
		}
	return 0;
	}

sub link {
	my $class = shift;
	my $text = shift;
	return undef unless defined $class->info->{filekey};
	my @reference = qw(analysisname casename patientid);
	unless(defined($text)) {
		foreach my $arg (@reference) {
			next unless defined $class->info->{$arg};
			$text = $class->info->{$arg};
			last;
			}
		}
	my $key = $class->info->{filekey};
	if ($class->info->{filetype} eq 'folder') {
		return "=HYPERLINK(\"https://drive.google.com/drive/u/0/folders/$key\";\"$text\")";
		}
	if ($class->info->{filetype} eq 'spreadsheet') {
		return "=HYPERLINK(\"https://docs.google.com/spreadsheets/d/$key/\";\"$text\")";
		}
	return undef;
	}



































1;
