package Table::ClinicalInterpretation;

use strict;
use warnings;
use Dir::Self;
use parent 'Table';
use lib __DIR__;

use Aoddb;
use Atlas;
use File::Basename;
use Storable 'dclone';
use Encode qw(is_utf8 encode decode decode_utf8);
use List::Util qw(max);
use Mojo::Base -base;
use Data::Dumper;
use List::Util qw(sum min max);
use Encode::Detect::Detector;
use experimental 'smartmatch';
use Switch;
my $local_path = __DIR__ . '/';

has tablename	=> 'ClinicalInterpretation';
has id_field	=> 'clinicalinterpretationid';

my %ClinicalImplication;
$ClinicalImplication{1}    = encode('utf-8', 'Назначение терапии рекомендовано в соответствии с инструкцией по применению препарата и/или стандартов терапии заболевания (в РФ и/или зарубежом) (Уровень доказательности I)');
$ClinicalImplication{2}    = encode('utf-8', 'Предпочтительная опция терапии для прогрессирующего и/или рефрактерного заболевания (off-label или в рамках клинических исследований) (Уровень доказательности II)');
$ClinicalImplication{'3A'} = encode('utf-8', 'Перспективная опция терапии для прогрессирующего и/или рефрактерного заболевания (off-label или в рамках клинических исследований) (Уровень доказательности III-A)');
$ClinicalImplication{'3B'} = encode('utf-8', 'Возможная опция терапии для прогрессирующего и/или рефрактерного заболевания (off-label или в рамках клинических исследований) (Уровень доказательности III-B)');
$ClinicalImplication{'3C'} = encode('utf-8', 'Возможная опция терапии для прогрессирующего и/или рефрактерного заболевания (off-label или в рамках клинических исследований) (Уровень доказательности III-C)');
$ClinicalImplication{4}    = encode('utf-8', 'Терапия может быть рекомендована в рамках клинических исследований в случае прогрессирования заболевания и/или исчерпания опций лечения (Уровень доказательности 4)');
$ClinicalImplication{'R1'} = encode('utf-8', 'Назначение терапии не рекомендовано в соответствии с инструкцией по применению препарата и/или стандартов терапии заболевания (в РФ и/или зарубежом) (Уровень доказательности R1)');
$ClinicalImplication{'R2'} = encode('utf-8', 'При рассмотрении опций терапии рекомендуем принять во внимание более высокий риск прогрессирования заболевания на фоне терапии (Уровень доказательности R2)');


our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub Player {
	my $class = shift;
	return Table::Player->fetch($class->{DB}, $class->info->{playername});
	}

sub purgeRCT { # remove all data from RecommendationCT table for this Clinical Interpretation
	my $class = shift;
	my $sql_cmd = "select COUNT(*) FROM RecommendationCT where clinicalInterpretationId = '".$class->get_id."';";
	if ($class->{DB}->execute_select_single($sql_cmd)) {
		my $sql_cmd = "delete from RecommendationCT where clinicalInterpretationId = '".$class->get_id."';";
		my $sth = $class->{DB}->execute($sql_cmd);
		}
	}

sub purgeRGC { # remove all data from RecommendationGC table for this Clinical Interpretation
	my $class = shift;
	my $sql_cmd = "select COUNT(*) FROM RecommendationGC where clinicalInterpretationId = '".$class->get_id."';";
	if ($class->{DB}->execute_select_single($sql_cmd)) {
		my $sql_cmd = "delete from RecommendationGC where clinicalInterpretationId = '".$class->get_id."';";
		my $sth = $class->{DB}->execute($sql_cmd);
		}
	}

sub purgeRTP { # remove all data from RecommendationTP table for this Clinical Interpretation
	my $class = shift;
	my $sql_cmd = "select COUNT(*) FROM RecommendationTP where clinicalInterpretationId = '".$class->get_id."';";
	if ($class->{DB}->execute_select_single($sql_cmd)) {
		my $sql_cmd = "delete from RecommendationTP where clinicalInterpretationId = '".$class->get_id."';";
		my $sth = $class->{DB}->execute($sql_cmd);
		}
	}

sub RCTs {
	my $class = shift;
	
	my @result;
	my $sql_cmd = "select recommendationctid from RecommendationCT where clinicalInterpretationId = '".$class->get_id."';";
	my $sth = $class->{DB}->execute($sql_cmd);
	while (my $row = $sth->fetchrow_arrayref) {
		push @result, Table::RecommendationCT->fetch($class->{DB}, $$row[0]);
		}
	return @result;
	}

sub RTPs {
        my $class = shift;

        my @result;
        my $sql_cmd = "select recommendationtpid from RecommendationTP where clinicalInterpretationId = '".$class->get_id."';";
        my $sth = $class->{DB}->execute($sql_cmd);
        while (my $row = $sth->fetchrow_arrayref) {
                push @result, Table::RecommendationTP->fetch($class->{DB}, $$row[0]);
                }
        return @result;
        }

sub RGCs {
        my $class = shift;

        my @result;
        my $sql_cmd = "select recommendationgcid from RecommendationGC where clinicalInterpretationId = '".$class->get_id."';";
        my $sth = $class->{DB}->execute($sql_cmd);
        while (my $row = $sth->fetchrow_arrayref) {
                push @result, Table::RecommendationGC->fetch($class->{DB}, $$row[0]);
                }
        return @result;
        }

sub Case {
	my $class = shift;
	return $class->{DB}->Case($class->info->{casename});
	}

sub prepareRCT {
	my $class = shift;
	my $data = shift;
	
	my $DB = $class->{DB};
	my $result;
	$result->{message} = undef;
	$result->{result} = [];

	my $Case = $class->Case;
	my $nct_id = uc($data->{nctid});
	my $NCT = $Case->{DB}->NCT($nct_id);
	unless (defined($NCT->{content})) {
		# print STDERR $NCT;
		$result->{message} = "conflict parsing CT list: $nct_id - problem with identifier";
		return $result;
		}
	my $description = $data->{description};
	my $title = $data->{title};
	my @mutation_input = split/\+/, $data->{"variant"};
	my @mutation_output;
	#print STDERR Dumper \@mutation_input;
	my $marker_name;
	foreach my $mutation (@mutation_input) {
		my $var;
		$var = $Case->parseVariantText($mutation);
		$var = $Case->parseCNVText($mutation) unless defined $var->{result};
		unless (defined ($var->{result})) {
			$marker_name = $mutation;
			next;
			}
		return "Failed to parse $mutation" unless defined $var->{result};
		push (@mutation_output, $var->{result}->name);
		}
	#my $MT = Table::MolecularTarget->forceFetch($DB, $mutation->{result}->name);
	my $MT;
	if (scalar @mutation_output > 0) {
		$MT = Table::MolecularTarget->forceFetch($DB, join(';', @mutation_output));
		}
	if ((length($description) <= 1)and(defined($MT))) {
		$description = $MT->generateCTDescr_r;
		}
	if ((length($title) <= 1)and(defined($MT))) {
		$title = $MT->generateTitle_r;
		}
	my $drugString = lc($data->{drugs});
	my @arms;
	if (length($drugString) < 2) {
		@arms = @{$NCT->drugList($MT->generateBiomarkerCode)};
		} else {
		if (defined($DB->parseDrugListString($drugString))) {
			push (@arms, [$DB->parseDrugListString($drugString)]);
			} else {
			$result->{message} = "conflict parsing CT list: provided drug list could not be parsed, one of the drug is unknown $drugString";
			return $result;
			}
		}
	foreach my $drugList (@arms) {
		my $info;
		$info->{clinicalinterpretationid} = $class->get_id;
		$info->{moleculartargetid} = $MT->get_id if defined($MT);
		$info->{markername} = $marker_name if defined($marker_name);
		$info->{NCTid} = $nct_id;
		$info->{moleculartargettitle} = $title;
		$info->{recommendationdescription} = $description;
		$info->{treatmentschemeid} = (Table::TreatmentScheme->forceFetch($DB, join(',', @{$drugList})))->get_id;
		push (@{$result->{result}}, $info);
		}
	return $result;
	}

sub prepareRGC {
	my $class = shift;
	my $data = shift;
	
	my $DB = $class->{DB};
	my $result;
	$result->{message} = undef;
	$result->{result} = [];

	my $Case = $class->Case;
	my $mutation = $data->{"variant"};
	$mutation = $Case->parseVariantText($mutation);
	unless (defined($mutation->{result})) {
		my $result->{message} = $mutation->{message};
		return $result;
		}
	my $MT = Table::MolecularTarget->forceFetch($DB, $mutation->{result}->name);
	my $info;
	$info->{clinicalinterpretationid} = $class->get_id;
	$info->{moleculartargetid} = $MT->get_id;
	push @{$result->{result}}, $info;
	return $result;
	}

sub prepareRTP {
	my $class = shift;
	my $data = shift;
	
	my $DB = $class->{DB};
	my $result;
	$result->{message} = undef;
	$result->{result} = [];
	
	my $Case = $class->Case;
	my $drugString = lc($data->{drug});
	my $TS = Table::TreatmentScheme->forceFetch($DB, $drugString);
	unless (defined($TS)) {
		$result->{message} = "conflict parsing Biomarker list: provided drug list could not be parsed, one of the drug is unknown ($drugString)";
		return $result;
		}

	my $info;
	$info->{clinicalinterpretationid} = $class->get_id;
	$info->{therapyrecommendationtype} = $data->{recommendation};
	$info->{confidencelevel} = uc($data->{loe});
	$info->{treatmentschemeid} = $TS->get_id;
	$info->{markername} = $data->{biomarker};
	$info->{description} = $data->{description};

	my $mutation;
	$mutation = $Case->parseVariantText($data->{"mutation"});
	$mutation = $Case->parseCNVText($data->{"mutation"}) unless defined $mutation->{result};
	unless (defined($mutation->{result})) {
		#my $result->{message} = $mutation->{message};
		#return $result;
		} else {
		my $MT = Table::MolecularTarget->forceFetch($DB, $mutation->{result}->name);
		$info->{moleculartargetid} = $MT->get_id;
		}
	push @{$result->{result}}, $info;
	return $result;
	}

sub report {
	my $class = shift;
	##print STDERR Dumper $class->info;
	my $folderKey = $class->Case->GDFile->info->{filekey};
	my $file = $class->report_generate;
	if ($class->{error}) {
		return $class->{error};
		}
	print STDERR "$file\n";
	Atlas::wrap_python("python3 $local_path/../..//Claudia.python_max/claudia/upload_file.py '$file' '$folderKey' 'application/pdf'");
	#$class->{DB}->{GD}->file_upload($file , $folderKey);
	}

sub report_prepare_reference_list {
	my $class = shift;
	my $template = shift;
	foreach my $ref (sort {$a cmp $b} (keys %{$template->{ReferenceRaw}})) {
		next if length($ref) < 2;
		push(@{$template->{Reference}}, {"Ref"=>"$ref"});
		}
	return $template;
	}

sub report_generate {
	my $class = shift;

	$class->get_PRoute_data;
	if ($class->check_PRoute_data eq 1) {
		print STDERR "HERE\n";
		return 1;
		}

	my $basename = $class->report_generate_file_name;
	my $filePDF  = $basename.".pdf";
	my $fileJSON = $basename.".json";
	print STDERR "LOG - Generating report template\n";
	my $template = $class->report_prepare_template;
	print STDERR "LOG - TMB Evaluation\n";
	$template = $class->report_evaluate_TMB($template);
	print STDERR "LOG - Generating Intro Section\n";
	$template = $class->report_generate_IntroSection($template);
	print STDERR "LOG - Generating NCT\n";
	$template = $class->report_gether_NCT($template);
	print STDERR "LOG - Generating CTrial Main\n";
	$template = $class->report_generate_CTrialMain($template);
	print STDERR "LOG - Generating Header\n";
	$template = $class->report_generate_header($template);
	print STDERR "LOG - Generating Major Comments\n";
	$template = $class->report_generate_MajorComments($template);
	print STDERR "LOG - Generating PBT\n";
	$template = $class->report_generate_PBT($template);
	print STDERR "LOG - Generating Main Description Result\n";
	$template = $class->report_generate_MainDescriptionResults($template);
	print STDERR "LOG - Generating Pharm Section\n";
	$template = $class->report_generate_Pharm($template);
	print STDERR "LOG - Generating NGS table SNV\n";
	$template = $class->report_generate_NGS_table_SNV($template);
	print STDERR "LOG - Generating NGS table CNV\n";
	$template = $class->report_generate_NGS_table_CNV($template);
	print STDERR "LOG - Generating NGS gene list DNA\n";
	$template = $class->report_generate_NGS_gene_list_DNA($template);
	print STDERR "LOG - Generating NGS gene list RNA\n";
	$template = $class->report_generate_NGS_gene_list_RNA($template);
	print STDERR "LOG - generating NGS QC report\n";
	$template = $class->report_generate_NGS_QC_report($template);
	print STDERR "LOG - Generating LT Results\n";
	$template = $class->report_generate_LTResults($template);
	print STDERR "LOG - Generating ALT Results\n";
	$template = $class->report_generate_ALTResults($template);
	print STDERR "LOG - Generating IHC Results\n";
	$template = $class->report_generate_IHC_results($template);
	print STDERR "LOG - Generating PCR Results\n";
	$template = $class->report_generate_PCR_results($template);
	print STDERR "LOG - Generating FISH Results\n";
	$template = $class->report_generate_FISH_results($template);
	print STDERR "LOG - Generating MSI Results\n";
	$template = $class->report_generate_MSI_results($template);
	print STDERR "LOG - Generating Methylation Results\n";
	$template = $class->report_generate_Methylation_results($template);
	print STDERR "LOG - Generating Pathomorphology Results\n";
	$template = $class->report_generate_pathomorphology_results($template);
	print STDERR "LOG - Generating Reference List\n";
	$template = $class->report_prepare_reference_list($template);
	print STDERR "LOG - Template DONE\n";
	
	$class->get_contractor;
	if (($class->info->{contractor} eq 'EMC')or($class->info->{contractor} eq 'Ilyinskaya')) {
		$template->{'isWhiteLabel'} = 1;
		} else {
		$template->{'isWhiteLabel'} = '-1';
		}
	if (defined($class->info->{contractor})) {
		$template->{'Contractor'} = $class->info->{contractor}
		} else {
		$template->{'Contractor'} = 'NA'
		}
	delete $template->{"ReferenceRaw"};
	
	$template = Atlas::json_to_data($template);
	open (my $json_fh, ">$fileJSON");
	print $json_fh $template;
	close $json_fh;
	$template = `cat $fileJSON`; chomp $template;
	my $command = "curl --header \"Content-Type: application/json\" --request POST --data '\@$fileJSON' https://report.oncoatlas.ru/ --output $filePDF 2> /dev/null";
	print STDERR "$command\n";
	#print STDERR "Encoding: ",Encode::Detect::Detector::detect($template),"\n";
	`$command`;
	if ($class->info->{contractor} eq 'EMC') {
		my $folder = $class->{DB}->{global_config}->{data_path}->{configPath};
		my $EMC_front = "$folder/pdf_source/EMC_front.pdf";
		my $EMC_back  = "$folder/pdf_source/EMC_back.pdf";
		my $command = "pdfunite $EMC_front $filePDF $EMC_back $filePDF.EMC";
		`$command`;
		`mv $filePDF.EMC $filePDF`;
		} elsif ($class->info->{contractor} eq 'Helix') {
		my $folder = $class->{DB}->{global_config}->{data_path}->{configPath};
		my $Helix_front = "$folder/pdf_source/Helix_front.pdf";
		my $command = "pdfunite $Helix_front $filePDF $filePDF.Helix";
		`$command`;
		`mv $filePDF.Helix $filePDF`;
		} elsif ($class->info->{contractor} eq 'Ilyinskaya') {
		my $folder = $class->{DB}->{global_config}->{data_path}->{configPath};
		my $Ilyinskaya_front = "$folder/pdf_source/Ilyinskaya_front.pdf";
		my $Ilyinskaya_back  = "$folder/pdf_source/Ilyinskaya_back.pdf";
		my $command = "pdfunite $Ilyinskaya_front $filePDF $Ilyinskaya_back $filePDF.Ilyinskaya";
		print STDERR "$command\n";
		`$command`;
		`mv $filePDF.Ilyinskaya $filePDF`;
		}
	print STDERR "$filePDF\n";
	return $filePDF;
	}

sub get_contractor {
	my $class = shift;

	my $contractor_string = Atlas::wrap_python("python $local_path/../../scripts/python/SS_grep_contractor.py ".$class->Case->InternalBarcode->get_id);
	chomp $contractor_string;
	$class->info->{contractor_string} = $contractor_string;
	$class->info->{contractor} = 'EMC' if (decode('UTF-8', $class->info->{contractor_string}) =~ 'ЕМС');
	$class->info->{contractor} = 'EMC' if (decode('UTF-8', $class->info->{contractor_string}) =~ 'EMC');
	$class->info->{contractor} = 'Helix' if (decode('UTF-8', $class->info->{contractor_string}) =~ 'Хеликс');
	$class->info->{contractor} = 'Helix' if (decode('UTF-8', $class->info->{contractor_string}) =~ 'ХЕЛИКС');
	$class->info->{contractor} = 'Ilyinskaya' if (decode('UTF-8', $class->info->{contractor_string}) =~ 'Ильинская');
	$class->info->{contractor} = 'Atlas' if ((decode('UTF-8', $class->info->{contractor_string}) =~ 'МЦ')and
						(decode('UTF-8', $class->info->{contractor_string}) =~ 'Атлас'));
	}

sub report_generate_IHC_results {
	my $class	= shift;
	my $template	= shift;
	
	$template->{IGH} = [];
	$class->get_PRoute_data unless defined($class->info->{PRoute_data});
	foreach my $LTRes (@{$class->info->{PRoute_data}}) {
		if (decode('utf-8', $LTRes->{LTMethod}) =~ /ИГХ/) {
			my $res;
			$res->{"IHCMarker"} = $LTRes->{biomarker};
			$res->{"IHCMarker"} = 'NTRK1, NTRK2, NTRK3' if uc($LTRes->{biomarker}) eq 'PAN-TRK';
			$res->{"IHCMarker"} = 'dMMR' if uc($LTRes->{biomarker}) eq 'DMMR';
			$res->{"IHCResultShort"} = $LTRes->{LTRes};
			$res->{"IHCResultLong"} = "Enter Methodology and Result Description Here";
			$res->{"IHCContractor"} = "Enter Contractor Here";
			push(@{$template->{IGH}}, $res);
			}
		}


	
	return $template;
	}

sub report_generate_PCR_results {
	my $class       = shift;
	my $template    = shift;
	
	$template->{PCR} = [];
	$class->get_PRoute_data unless defined($class->info->{PRoute_data});
	foreach my $LTRes (@{$class->info->{PRoute_data}}) {
		if (decode('utf-8', $LTRes->{LTMethod}) =~ /ПЦР/) {
			my $res;
			$res->{"PCRMarker"} = $LTRes->{biomarker};
			$res->{"PCRResultShort"} = $LTRes->{LTRes};
			$res->{"PCRResultLong"} = "Enter Methodology and Result Description Here";
			$res->{"PCRContractor"} = "Enter Contractor Here";
			push(@{$template->{PCR}}, $res);
			}
		}
	return $template;
	}

sub report_generate_FISH_results {
	my $class       = shift;
	my $template    = shift;
	
	$template->{FISH} = [];
	$class->get_PRoute_data unless defined($class->info->{PRoute_data});
	#print STDERR Dumper $class->info->{PRoute_data};
	foreach my $LTRes (@{$class->info->{PRoute_data}}) {
		if (decode('utf-8', $LTRes->{LTMethod}) =~ /FISH/) {
			my $res;
			$res->{"FISHMarker"} = $LTRes->{biomarker};
			$res->{"FISHResultShort"} = $LTRes->{LTRes};
			$res->{"FISHResultLong"} = "Enter Methodology and Result Description Here";
			$res->{"FISHContractor"} = "Enter Contractor Here";
			push(@{$template->{FISH}}, $res);
			}
		}
	return $template;
	}

sub report_generate_MSI_results {
	my $class	= shift;
	my $template	= shift;
	
	$template->{MSI} = [];
	$class->get_PRoute_data unless defined($class->info->{PRoute_data});
	foreach my $LTRes (@{$class->info->{PRoute_data}}) {
		if ($LTRes->{biomarker} =~ /MSI/) {
			my $res;
			$res->{"MSIDescr"} = "Enter Methodology Here";
			if ($LTRes->{LTRes} =~ /MSS/) {
				$res->{"MSIResult"} = encode('utf-8', "Микросателлитной нестабильности в исследуемых локусах не выявлено. Опухоль имеет MSI стабильный (MSS) статус");
				} else {
				$res->{"MSIResult"} = "Enter Methodology and Result Description Here";
				}
			$res->{"MSIContractor"} = "Enter Contractor Here";
			push(@{$template->{MSI}}, $res);
			}
		}
	return $template;
	}

sub report_generate_Methylation_results {
	my $class       = shift;
	my $template    = shift;
	
	$template->{Methylation} = [];
	return $template;;
	$class->get_PRoute_data unless defined($class->info->{PRoute_data});
	foreach my $LTRes (@{$class->info->{PRoute_data}}) {
		if ($LTRes->{biomarker} =~ /MSI/) {
			my $res;
			$res->{"MSIDescr"} = "Enter Methodology Here";
			if ($LTRes->{LTRes} =~ /MSS/) {
				$res->{"MSIResult"} = encode('utf-8', "Микросателлитной нестабильности в исследуемых локусах не выявлено. Опухоль имеет MSI стабильный (MSS) статус");
				} else {
				$res->{"MSIResult"} = "Enter Methodology and Result Description Here";
				}
			$res->{"MSIContractor"} = "Enter Contractor Here";
			push(@{$template->{MSI}}, $res);
			}
		}
	return $template;
	}

sub report_generate_CTrialMain {
	my $class	= shift;
	my $template	= shift;
	my $count = 0;
	
	foreach my $RCT ($class->RCTs) {
		++$count;
		}
	if ($count eq 0) {
		$template->{CTrialMain} = encode('utf-8', "Биомаркеры для включения в клинические исследования молекулярно-направленной терапии не обнаружены");
		} else {
		my $word;
		if (($count =~ /11$/)or($count =~ /12$/)or($count =~ /13$/)or($count =~ /14$/)) {
			$word = "релевантных клинических исследований";
			} elsif ($count =~ /1$/) {
			$word = "релевантное клиническое исследование";
			} elsif (($count =~ /2$/)or($count =~ /3$/)or($count =~ /4$/)) {
			$word = "релевантных клинических исследования";
			} else {
			$word = "релевантных клинических исследований";
			}
		$template->{CTrialMain} = encode('utf-8', "Мы подобрали $count наиболее $word на основании молекулярного профиля опухоли (подробнее см. раздел “Навигатор по клиническим исследованиям”).");
		}
	return $template;
	}

sub report_generate_ALTResults {
	my $class	= shift;
	my $template	= shift;
	$template->{ALTResults} = [];
	return $template;
	}

sub report_generate_PBT {
	my $class	= shift;
	my $template	= shift;
	
	$template->{PBT} = [];
	$template->{LOBT} = [];
	$template->{ToxT} = [];
	my $recommendation = {};
	foreach my $RTP ($class->RTPs) {
		#print STDERR Dumper $RTP->info;
		my $recType = 'PBT'; # PBT or LOBT
		if ((uc($RTP->info->{therapyrecommendationtype}) eq 'TR')) {
			$recType = 'LOBT';
			}
		my $id = $RTP->TreatmentScheme->get_id;
		$recommendation->{$recType}->{$id} = {} unless defined $recommendation->{$recType}->{$id};
		$recommendation->{$recType}->{$id}->{asterics} = 1 unless defined $recommendation->{$recType}->{$id}->{asterics};
		$recommendation->{$recType}->{$id}->{BM}  = [] unless defined $recommendation->{$recType}->{$id}->{BM};
		$recommendation->{$recType}->{$id}->{LoE} = [] unless defined $recommendation->{$recType}->{$id}->{LoE};
		push (@{$recommendation->{$recType}->{$id}->{LoE}}, uc($RTP->info->{confidencelevel}));
		push (@{$recommendation->{$recType}->{$id}->{BM}}, uc($RTP->info->{markername}));
		if (defined($RTP->info->{moleculartargetid})) {
			my $MT = Table::MolecularTarget->fetch($class->{DB}, $RTP->info->{moleculartargetid});
			my @BM;
			foreach my $MR ($MT->mutationRules) {
				push @BM, encode('utf-8', $MR->Mutation->VariantAnnotation->Transcript->Gene->info->{genesymbol} . ' ' . $MR->Mutation->HGVS_name);
				}
			foreach my $CNV ($MT->CNVs) {
				push (@BM, encode('utf-8', 'Делеция' . uc($CNV->Gene->info->{genesymbol}))) if $CNV->info->{type} eq 'del';
				push (@BM, encode('utf-8', 'Амплификация' . uc($CNV->Gene->info->{genesymbol}))) if $CNV->info->{type} eq 'amp';
				}
			$recommendation->{$recType}->{$id}->{BM} = \@BM;
			}
		if (lc($RTP->info->{therapyrecommendationtype}) eq 'in-label') {
			$recommendation->{$recType}->{$id}->{asterics} = 0;
			}
		}
	#print STDERR Dumper $recommendation;
	foreach my $r (sort {
			join('', sort {$a cmp $b} @{$recommendation->{PBT}->{$a}->{LoE}}) cmp join('', sort {$a cmp $b} @{$recommendation->{PBT}->{$b}->{LoE}}) || 
			join(',',$recommendation->{PBT}->{$a}->{BM}) cmp join(',', $recommendation->{PBT}->{$b}->{BM}) ||
		       Table::TreatmentScheme->fetch($class->{DB}, $a)->drugString cmp Table::TreatmentScheme->fetch($class->{DB}, $b)->drugString ||
		       $recommendation->{PBT}->{$a}->{asterics} <=> $recommendation->{PBT}->{$b}->{asterics}
		} keys %{$recommendation->{PBT}}) {
		#print STDERR "!-",join(',', @{$recommendation->{PBT}->{$r}->{LoE}}),"\t",
		#	"BM-",join(',',@{$recommendation->{PBT}->{$r}->{BM}}),"\t",
		#	Table::TreatmentScheme->fetch($class->{DB}, $r)->drugString,"\n";
		my $result;
		my $TS = Table::TreatmentScheme->fetch($class->{DB}, $r);
		$result->{Drug} = encode('utf-8', join('+', $TS->drugList));
		$result->{LoE}  = join(',', @{$recommendation->{PBT}->{$r}->{LoE}});
		$result->{BM}  = join(',', @{$recommendation->{PBT}->{$r}->{BM}});
		if ($recommendation->{PBT}->{$r}->{asterics} eq 1) {
			$result->{Drug} = $result->{Drug}.'*';
			$template->{"Disclaimer"} = {} unless (defined($template->{"Disclaimer"}));
			$template->{"Disclaimer"}->{OFFLabel} = encode('utf-8', "* Препарат не зарегистрирован для применения на территории РФ для данного показания (подробнее в разделе \"Информация о Лекарственных Средствах\")");
			}
		push @{$template->{PBT}}, $result;
		}
	foreach my $r (sort {
			join('', sort {$a cmp $b} @{$recommendation->{LOBT}->{$a}->{LoE}}) cmp join('', sort {$a cmp $b} @{$recommendation->{LOBT}->{$b}->{LoE}}) ||
			$recommendation->{LOBT}->{$a}->{BM} <=> $recommendation->{LOBT}->{$b}->{BM} ||
			Table::TreatmentScheme->fetch($class->{DB}, $a)->drugString cmp Table::TreatmentScheme->fetch($class->{DB}, $b)->drugString ||
			$recommendation->{LOBT}->{$a}->{asterics} <=> $recommendation->{LOBT}->{$b}->{asterics}
		} keys %{$recommendation->{LOBT}}) {
		my $result;
		my $TS = Table::TreatmentScheme->fetch($class->{DB}, $r);
		$result->{Drug} = encode('utf-8', join('+', $TS->drugList));
		$result->{LoE}  = join(',', @{$recommendation->{LOBT}->{$r}->{LoE}});
		$result->{BM}  = join(',', @{$recommendation->{LOBT}->{$r}->{BM}});
		if ($recommendation->{LOBT}->{$r}->{asterics} eq 1) {
			$result->{Drug} = $result->{Drug}.'*';
			$template->{"Disclaimer"} = {} unless (defined($template->{"Disclaimer"}));
			$template->{"Disclaimer"}->{OFFLabel} = encode('utf-8', "* Препарат не зарегистрирован для применения на территории РФ для данного показания (подробнее в разделе \"Информация о Лекарственных Средствах\")");
			}
		push @{$template->{LOBT}}, $result;
		}
	my $resultDummy;
	$resultDummy->{Drug} = '-';
	$resultDummy->{LoE} = '-';
	$resultDummy->{BM} = encode('utf-8', 'Биомаркеры не выявлены');
	
	for (my $i = 0; $i < scalar(@{$template->{PBT}}); $i++) {
		$template->{PBT}->[$i]->{'DrugColor'} = 'green';
		}
	for (my $i = 0; $i < scalar(@{$template->{LOBT}}); $i++) {
		$template->{LOBT}->[$i]->{'DrugColor'} = 'red';
		push @{$template->{PBT}}, $template->{LOBT}->[$i];
		}
	for (my $i = 0; $i < scalar(@{$template->{PBT}}); $i++) {
		$template->{PBT}->[$i]->{'LoE'} = $ClinicalImplication{$template->{PBT}->[$i]->{'LoE'}};
		}
	if (scalar(@{$template->{PBT}}) eq 0) {
		$template->{TermsSectionType} = 0;
		push @{$template->{PBT}}, $resultDummy;
		} else {
		$template->{TermsSectionType} = 1;
		}
	return $template;
	}

sub report_generate_MainDescriptionResults {
	my $class = shift;
	my $template = shift;
	
	my $recommendations = [];
	my $recommendationsFinal = [];
	$template->{TABLE} = [];
	return $template if (scalar ($class->RTPs) eq 0);
	$template = $class->report_evaluate_TMB($template) unless defined $template->{TMB};
	foreach my $RTP (sort {
			$a->info->{confidencelevel} cmp $b->info->{confidencelevel} ||
			$a->info->{markername} cmp $b->info->{markername} || 
			$a->TreatmentScheme->drugString cmp $b->TreatmentScheme->drugString ||
			$a->info->{therapyrecommendationtype} cmp $b->info->{therapyrecommendationtype}
			} $class->RTPs) {
		print STDERR $RTP->info->{confidencelevel},"\t",
			$RTP->info->{markername},"\t",
			$RTP->TreatmentScheme->drugString,"\n";
		my $rec;
		$rec->{Color} = 'green';
		if ((uc($RTP->info->{therapyrecommendationtype}) eq 'TR')) {
			$rec->{Color} = 'red';
			}
		$rec->{drugs} = [$RTP->TreatmentScheme->drugString];
		$rec->{Glines} = join(", ", sort {$a cmp $b} $RTP->guidelines);
		$rec->{DDescr} = encode('utf-8', "NA");
		$rec->{GADescr} = "NA";
		$rec->{GA} = "NA";
		$rec->{Meth} = "NA";
		$rec->{LoE} = uc($RTP->info->{confidencelevel});
		$rec->{DDescrLong} = $RTP->info->{description};
		if (defined($RTP->info->{moleculartargetid})) {
			$rec->{Meth} = "NGS";
			my $MT = Table::MolecularTarget->fetch($class->{DB}, $RTP->info->{moleculartargetid});
			my @result;
			my @name;
			foreach my $MR ($MT->mutationRules) {
				push @result, $MR->Mutation->HGVS_name;
				my $Gene = $MR->Mutation->VariantAnnotation->Transcript->Gene;
				push @name, (uc($Gene->info->{genesymbol}) . ' генетический вариант');
				if ($Gene->info->{istsg}) {
					$rec->{DDescr_eff} = encode('utf-8', " в связи с наличием повреждающего варианта в гене ".uc($Gene->info->{genesymbol}));
					} elsif ($Gene->info->{isoncogene}) {
					$rec->{DDescr_eff} = encode('utf-8', " в связи с наличием активирующей мутации гена ".uc($Gene->info->{genesymbol}));
					} else {
					$rec->{DDescr_eff} = encode('utf-8', " в связи с наличием онкогенного генетического варианта в гене ".uc($Gene->info->{genesymbol}));
					}
				}
			foreach my $CNV ($MT->CNVs) {
				push (@result, ('Вариации числа копий гена' . uc($CNV->Gene->info->{genesymbol}))) if $CNV->info->{type} eq 'amp';
				push (@result, ('Амплификация')) if $CNV->info->{type} eq 'amp';
				push (@result, ('Делеция')) if $CNV->info->{type} eq 'del';
				$rec->{DDescr_eff} = encode('utf-8', " в связи с наличием делеции ".uc($CNV->Gene->info->{genesymbol})) if $CNV->info->{type} eq 'del';
				$rec->{DDescr_eff} = encode('utf-8', " в связи с наличием амплификации ".uc($CNV->Gene->info->{genesymbol})) if $CNV->info->{type} eq 'amp';
				}
			$rec->{GADescr}	= encode('utf-8', join (', ', @name));
			$rec->{GA}	= encode('utf-8', join (', ', @result));
			} elsif (defined($RTP->info->{markername})and($RTP->info->{markername} =~ /tmb/)) {
			$rec->{Meth} = "NGS";
			if (($RTP->info->{markername} =~ /tmb\s*h/)or($template->{TMB} > 10)) {
				$rec->{GADescr} = encode('utf-8', "Высокая мутационная нагрузка (TMB-High)");
				$rec->{DDescr_eff} = encode('utf-8', " в связи с наличием высокой мутационной нагрузки");
				} else {

				$rec->{GADescr} = encode('utf-8', "Низкая мутационная нагрузка (TMB-Low)");
				$rec->{DDescr_eff} = encode('utf-8', " в связи с низкой мутационной нагрузкой");
				}
			$rec->{GA} = encode('utf-8', $template->{TMB} . " Мут/МБ");
			$rec->{DDescr} = encode('utf-8', "в связи с высокой мутационной нагрузкой");
			} elsif ((defined($RTP->info->{markername}))and(length($RTP->info->{markername}) > 1)) {
			$class->get_PRoute_data unless defined $class->info->{PRoute_data};
			my @markers_Meth;
			my @markers_GADescr;
			my @markers_GA;
			$rec->{DDescr_eff} = [];
			foreach my $LTRes (@{$class->info->{PRoute_data}}) {
				my $name1 = lc($RTP->info->{markername});
				$name1 =~ s/-//;
				my $name2 = lc($LTRes->{biomarker});
				$name2 =~ s/-//;
				if (($name1 eq 'er')and($name2 eq 'egr')) {$name2 = $name1}
				if (($name1 eq 'egr')and($name2 eq 'er')) {$name2 = $name1}
				if (($name1 eq 'pr')and($name2 eq 'pgr')) {$name2 = $name1}
				if (($name1 eq 'pgr')and($name2 eq 'pr')) {$name2 = $name1}
				if (($name1 eq 'her2')and($name2 eq 'erbb2')) {$name2 = $name1}
				if (($name1 eq 'erbb2')and($name1 eq 'her2')) {$name2 = $name1}

				if (($name1 =~ /$name2/)or($name2 =~ /$name1/)) {
					next if (($name1 eq 'er') and ($name2 ne 'er'));
					next if (($name2 eq 'er') and ($name1 ne 'er'));
					push @markers_Meth, $LTRes->{LTMethod};
					push @markers_GA, $LTRes->{LTRes};
					push @markers_GADescr, $LTRes->{LTBM};
					my $descr_eff = '';
					$descr_eff = 'микросателлитной стабильностью' if $LTRes->{LTRes} =~ /MSS/;
					$descr_eff = 'микросателлитной нестабильностью' if $LTRes->{LTRes} =~ /MSI/;
					$descr_eff = 'повышенным уровнем экспрессии '.$LTRes->{biomarker} if ((decode('utf-8', $LTRes->{LTRes}) =~ /оложит/)
												and(decode('utf-8', $LTRes->{LTMethod}) =~ /ИГХ/));
					$descr_eff = 'повышенным уровнем экспрессии '.$LTRes->{biomarker} if ((decode('utf-8', $LTRes->{LTRes}) =~ /овыш/)
												and(decode('utf-8', $LTRes->{LTMethod}) =~ /ИГХ/));
					$descr_eff = 'определенным уровнем экспрессии '.$LTRes->{biomarker} if ((length($descr_eff) < 1)
												and(decode('utf-8', $LTRes->{LTMethod}) =~ /ИГХ/));
					push @{$rec->{DDescr_eff}}, $descr_eff;
					}
				}
			$rec->{Meth} = join(',', uniq(sort {$a cmp $b} @markers_Meth));
			$rec->{GA} = join(',', @markers_GA);
			$rec->{GADescr} = join(',', @markers_GADescr);
			if (scalar @{$rec->{DDescr_eff}} > 1) {
				$rec->{DDescr_eff} = encode('utf-8', ' в связи с ' . join(', ', @{$rec->{DDescr_eff}}[0..(scalar @{$rec->{DDescr_eff}} - 2)]) 
						. ' и ' . @{$rec->{DDescr_eff}}[(scalar @{$rec->{DDescr_eff}} - 1)]);
				} else {
				$rec->{DDescr_eff} = encode('utf-8', ' в связи с ' . $rec->{DDescr_eff}->[0]);
				}
			}
		push @{$recommendations}, $rec;
		foreach my $Ref ($RTP->references) {
			print STDERR "HERE?\n";
			print STDERR Dumper $Ref->info;
			$template->{ReferenceRaw}->{parse_doi($Ref->info->{doi})} = 1;
			}
		}
	#print STDERR Dumper $recommendations;
	my $recommendationPrev;
	my $rCurrent;
	
	my @recArray = sort {
			$a->{LoE} cmp $b->{LoE} ||
			length_or_undef($a->{Glines}) <=> length_or_undef($b->{Glines}) ||
			$a->{DDescrLong} cmp $b->{DDescrLong} ||
			join(',', @{$a->{drugs}}) cmp join(',', @{$b->{drugs}})}
			@{$recommendations};
	push @{$recommendationsFinal}, $recArray[0];
	my $rCount = 0;
	for (my $r = 1; $r < scalar @recArray; $r++) {
		if (($recArray[$r]->{DDescrLong} eq $recArray[$r-1]->{DDescrLong})
			and($recArray[$r]->{GA} eq $recArray[$r-1]->{GA})) {
			push @{$recommendationsFinal->[$rCount]->{drugs}}, @{$recArray[$r]->{drugs}};
			} else {
			push @{$recommendationsFinal}, $recArray[$r];
			++$rCount;
			}
		}
	for (my $i = 0; $i < scalar @{$recommendationsFinal}; $i++) {
		if (scalar @{$recommendationsFinal->[$i]->{drugs}} > 1) {
			$recommendationsFinal->[$i]->{Drug} = encode('utf-8', 'Класс препаратов');
			$recommendationsFinal->[$i]->{"DDescr"} = encode('utf-8', "Класс препаратов (".join(", ", map {Table::TreatmentScheme->fetch($class->{DB}, $_)->drugList} @{$recommendationsFinal->[$i]->{drugs}}).")");
			$recommendationsFinal->[$i]->{"DDescr"} .= encode('utf-8', ' потенциально эффективен') if $recommendationsFinal->[$i]->{"Color"} eq 'green';
			$recommendationsFinal->[$i]->{"DDescr"} .= encode('utf-8', ' потенциально неэффективен') if $recommendationsFinal->[$i]->{"Color"} eq 'red';
			} else {
			$recommendationsFinal->[$i]->{Drug} = encode('utf-8', join(' + ', Table::TreatmentScheme->fetch($class->{DB}, $recommendationsFinal->[$i]->{drugs}->[0])->drugList));
			if (scalar (Table::TreatmentScheme->fetch($class->{DB}, $recommendationsFinal->[$i]->{drugs}->[0])->drugList) > 1) {
				$recommendationsFinal->[$i]->{"DDescr"} = encode('utf-8', "Комбинация препаратов (".join(", ", Table::TreatmentScheme->fetch($class->{DB}, $recommendationsFinal->[$i]->{drugs}->[0])->drugList).")");
				$recommendationsFinal->[$i]->{"DDescr"} .= encode('utf-8', ' потенциально эффективна') if $recommendationsFinal->[$i]->{"Color"} eq 'green';
				$recommendationsFinal->[$i]->{"DDescr"} .= encode('utf-8', ' потенциально неэффективна') if $recommendationsFinal->[$i]->{"Color"} eq 'red';
				} else {
				$recommendationsFinal->[$i]->{"DDescr"} = encode('utf-8', 'Препарат потенциально эффективен') if $recommendationsFinal->[$i]->{"Color"} eq 'green';
				$recommendationsFinal->[$i]->{"DDescr"} = encode('utf-8', 'Препарат потенциально неэффективен') if $recommendationsFinal->[$i]->{"Color"} eq 'red';
				}
			}
		$recommendationsFinal->[$i]->{"DDescr"} .= $recommendationsFinal->[$i]->{"DDescr_eff"};
		}
	$template->{TABLE} = $recommendationsFinal;
	return $template
	}

sub length_or_undef {
	my $string = shift;
	return 0 unless defined $string;
	return length($string);
	}	

sub report_generate_EffResultsDescription {
	my $class	= shift;
	my $template	= shift;
	
	
	
	return $template;
	}

sub report_evaluate_TMB {
	my $class	= shift;
	my $template	= shift;
	
	my %panel;
	foreach my $Barcode (sort {($b->info->{dataacquisitiondate} || '0000-00-00 00:00:00') cmp ($a->info->{dataacquisitiondate} || '0000-00-00 00:00:00')} $class->Case->barcodes) {
		next unless defined $Barcode->LibraryQC;
		next unless defined $Barcode->LibraryQC->info->{result};
		next unless $Barcode->LibraryQC->info->{result} eq 'PASS';
		next unless defined $Barcode->info->{panelcode};
		next if $Barcode->info->{panelcode} eq 'OCAV3RNA';
		next if defined($panel{$Barcode->info->{panelcode}});
		$panel{$Barcode->info->{panelcode}} = $Barcode;
		}
	foreach my $Barcode (sort {($b->info->{dataacquisitiondate} || '0000-00-00 00:00:00') cmp ($a->info->{dataacquisitiondate} || '0000-00-00 00:00:00')} $class->Case->barcodes) {
		next unless defined $Barcode->info->{panelcode};
		next if defined($panel{$Barcode->info->{panelcode}});
		next if $Barcode->info->{panelcode} eq 'OCAV3RNA';
		$panel{$Barcode->info->{panelcode}} = $Barcode;
		}
	my $mutation_count = 0; #Count of mutation for TMB calculation
	my $seed = 1000 + int(rand(8999));
	my $tmp_bed = $class->{DB}->config->{data_path}->{tmpPath}."/".$class->Case->get_id."_BED$seed.bed";
	my %panel_info;
	my $COUNT = 0;
	foreach my $panel_code (keys %panel) {
		my $Barcode = $panel{$panel_code};
		next unless defined $Barcode->major_AN;
		my $bed_file = $Barcode->panel_bed;
		$COUNT += 1;
		`cat $bed_file >> $tmp_bed`;
		$mutation_count += $Barcode->major_AN->TMB_mutation_count;
		}
	if ($COUNT eq 0) {
		$template->{TMB} = "-1";
		return $template;
		}
	`sort -k1,1 -k2,2n $tmp_bed > $tmp_bed.tmp`;
	`bedtools merge -i $tmp_bed.tmp > $tmp_bed`;
	`rm $tmp_bed.tmp`;
	my $exome_bed = $class->{DB}->{global_config}->{data_path}->{exome_bed};
	my $total_region = `bedtools intersect -a $tmp_bed -b $exome_bed -sorted | sort -k1,1 -k2,2n | sort -u | awk '{s=s+\$3-\$2;print s}' | tail -n1`;
	chomp $total_region;
	#print STDERR "$mutation_count\n";
	#print STDERR "$total_region\n";
	if ($total_region > 500000) {
		$template->{TMB} = int(10*($mutation_count*1000000/$total_region))/10;
		} else {
		$template->{TMB} = "-1";
		}
	
	return $template;
	}

sub get_panels_analysed {
	my $class	= shift;
	my @panels;
	foreach my $Barcode ($class->Case->barcodes) {
		push (@panels, $Barcode->info->{panelcode});
		}
	@panels = sort {$a cmp $b} @panels;
	return @panels;
	}

sub get_panels_analysed_string {
	my $class	= shift;
	return join('',uniq(sort {$a cmp $b} ($class->get_panels_analysed)));
	}	

sub get_gene_list {
	my $class	= shift;
	my $type	= shift;
	my %list;
	foreach my $Barcode ($class->Case->barcodes) {
		next unless defined $Barcode->major_AN;
		map {$list{$_} = 0} $Barcode->gene_list($type);
		}
	return (keys %list);
	}

sub report_generate_IntroSection {
	my $class	= shift;
	my $template	= shift;
	
	$template = $class->report_generate_goal($template);
	$template->{'TestType'} = encode('UTF-8', 'Solo Генетика');
	$template->{'TestType'} = encode('UTF-8', 'Solo ABC') if ($class->get_panels_analysed_string eq 'AODABCV1');
	$template->{'TestType'} = encode('UTF-8', 'Solo Комплекс') if (($class->get_panels_analysed_string =~ 'AODABCV1')and($class->get_panels_analysed_string =~ 'RCMGLYNCHV1'));
	$template->{'TestType'} = encode('UTF-8', 'Solo Комплекс') if ($class->get_panels_analysed_string =~ 'CCP');
	#print STDERR $class->get_panels_analysed_string,"\n";
	#print STDERR scalar($class->get_panels_analysed),"\n";
	$template->{'TestType'} = encode('UTF-8', 'Solo Комплекс') if (($class->get_panels_analysed_string =~ 'CHPV2')and(scalar($class->get_panels_analysed) > 1));
	$template->{'TestType'} = encode('UTF-8', 'Solo Комплекс') if (scalar($class->get_gene_list) > 50);

	$template->{ReferenceRaw}->{parse_doi("10.1200/PO.17.00011")} = 1;
	$template->{ReferenceRaw}->{parse_doi("10.1016/j.annonc.2020.07.014")} = 1;
	$template->{ReferenceRaw}->{parse_doi("10.1016/j.jmoldx.2016.10.002")} = 1;
	$template->{ReferenceRaw}->{parse_doi("10.1093/annonc/mdy263")} = 1;
	
	return $template;
	}

sub report_gether_NCT {
	my $class	= shift;
	my $template	= shift;

	my @result;
	foreach my $RCT ($class->RCTs) {
		my $CTData = $RCT->info->{nctid};
		$CTData = $class->{DB}->NCT($CTData)->locate;
		my $CTData_copy = $CTData;
		my $ustring = eval { decode( 'utf8', $CTData_copy, Encode::FB_CROAK ) }
			or next;
		$CTData = Atlas::data_to_json($CTData);
		$CTData->{CTrialGA} = $RCT->info->{moleculartargettitle};
		$CTData->{CTrialDescr} = $RCT->info->{recommendationdescription};
		foreach my $AS ($RCT->TreatmentScheme->activeSubstances) {
			#print STDERR $AS->info->{activesubstancename_r},"\n";
			my $drugName = ($AS->info->{activesubstancename_r} ? Atlas::uppercase_firstOnly($AS->info->{activesubstancename_r}) : Atlas::uppercase_firstOnly($AS->info->{activesubstancename}));
			push (@{$CTData->{DrugList}}, 
				{"CTDrug" => encode('UTF-8', $drugName)});
			}
		push(@result, $CTData);
		}
	$template->{TABLECli} = [@result];
	return $template;
	}

sub report_generate_header {
	my $class = shift;
	my $template = shift;
	
	my $gender = $class->Case->Patient->info->{sexid};
	my $genderFull = $gender;
	$gender =~ s/0/Жен./;
	$gender =~ s/1/Муж./;
	$genderFull =~ s/0/Женский/;
	$genderFull =~ s/1/Мужской/;
	$genderFull = encode('UTF-8', $genderFull);
	$gender = encode('UTF-8', $gender);
	$template->{Name} = encode('UTF-8', $class->Case->Patient->full_name);
	$template->{ID} = $class->Case->InternalBarcode->get_id;
	$template->{BDate} = Atlas::reformat_date($class->Case->Patient->info->{patientdob});
	$template->{RDate} = Atlas::reformat_date(Atlas::current_time('date'));
	$template->{Gender} = $gender;
	$template->{GenderFull} = $genderFull;
	my $pathology = $class->Case->BaselineStatus->info->{pathologycodebaseline}; # get pathology code
	$pathology = 'healthy' unless defined $pathology;
	print STDERR "pathology - n - '$pathology'\n";
	$pathology = Atlas::wrap_python("python $local_path/../../scripts/python/SS_pathology_name_v2.py $pathology nominative");
	chomp $pathology;
	$template->{Disease} = $pathology; # get pathology name in genitive
	my $SID = Atlas::wrap_python("python $local_path/../../scripts/python/SS_specimen_id.py ".$class->Case->InternalBarcode->get_id);
	$SID = [split/\n/,$SID];
	if ((defined($SID->[0]))and(decode('utf-8', $SID->[0]) eq 'кровь')) {
		$SID->[0] = $SID->[0] . ' (' . encode('UTF-8', $class->Case->Patient->major_name) . ')';
		}
	$template->{SID} = $SID->[0];
	$template->{SSource} = Atlas::wrap_python("python $local_path/../../scripts/python/SS_get_Cell.py ".$class->Case->PRoute->info->{filekey}." Requisition B5");
	#$template->{CDate} = (length($class->Case->info->{'profiledateday'}) < 2 ? '0' : '').$class->Case->info->{'profiledateday'}.'.'.(length($class->Case->info->{'profiledatemonth'}) < 2 ? '0' : '').$class->Case->info->{'profiledatemonth'}.'.'.$class->Case->info->{'profiledateyear'};
	$template->{CDate} = $class->Case->CDate;
	$template->{Diagnosis} = $class->Case->BaselineStatus->info->{diagnosismain};
	return $template;
	}

sub report_generate_goal {
	my $class = shift;
	my $template = shift;
	
	my $pathology = $class->Case->BaselineStatus->info->{pathologycodebaseline}; # get pathology code
	$pathology = 'healthy' unless defined $pathology;
	print STDERR "pathology - g - '$pathology'\n";
	$pathology = Atlas::wrap_python("python $local_path/../../scripts/python/SS_pathology_name_v2.py $pathology genitive"); # get pathology name in genitive
	$pathology =~ s/^\s+|\s+$//g;
	$pathology = decode("UTF-8", $pathology);
	my $goal;
	$goal = encode('UTF-8', "Целью проводимого исследования является анализ биомаркеров, ассоциированных с потенциальной эффективностью терапии $pathology.<br><br>");
	my @panels;
	foreach my $Barcode ($class->Case->barcodes) {
		push (@panels, $Barcode->info->{panelcode});
		}
	$template = $class->report_evaluate_TMB($template) unless defined $template->{TMB};
	if (join('',uniq(@panels)) eq 'AODABCV1') {
		$goal = $goal.encode('UTF-8', "В рамках исследования проанализирована кодирующая последовательность генов ATM, BRCA1, BRCA2, CHEK2 методом высокопроизводительного секвенирования (если не оговорено иное, см. раздел \"Результаты секвенирования\"). Клиническая интерпретация выполняется в соответствии с принципами доказательной медицины следуя международным рекомендациям в области прецизионной онкологии (ESMO, ASCO) на основании собственной базы знаний, включающей международные и отечественные клинические руководства (NCCN/ASCO/ESMO/АОР), а также результаты клинических и доклинических исследований.");
		$template->{"Goal"} = $goal;
		return $template;
		} else {
		my %list;
		my @active = qw(BARD1 1 BRIP1 1 CHEK2 1 CDK12 1 PALB2 1 RET 1 BRAF 1 BRCA1 1 BRCA2 1 ATM 1 EGFR 1 MET 1 ERBB2 1 KIT 1 PDGFRA 1 AKT1 1 FGFR1 1 FGFR2 1 FGFR3 1 FGFR4 1 IDH1 1 IDH2 1 KRAS 1 NRAS 1 PIK3CA 1 NF1 1 NOTCH1 1 PTEN 1); # list of clinically actionable genes;
		my %active_list = @active;
		my $active_analysed = [];
		foreach my $Barcode ($class->Case->barcodes) {
			map {$list{$_} = 0} $Barcode->gene_list;
			foreach my $arg ($Barcode->gene_list) {
				push @{$active_analysed}, $arg if defined($active_list{$arg});
				}
			}
		my $gene_count = scalar(keys %list);
		$active_analysed = join(', ', sort {$a cmp $b} uniq(@{$active_analysed}));
		$goal = $goal.encode('UTF-8', "В рамках исследования проанализированы $gene_count генов, в том числе следующие: $active_analysed");
		$class->get_PRoute_data unless defined($class->info->{PRoute_data});
		if (scalar(@{$class->info->{PRoute_data}}) > 0) {
			my @additional;
			foreach my $LTB (sort {$a->{LTMethod} cmp $b->{LTMethod}} @{$class->info->{PRoute_data}}) {
				next if $LTB->{LTBM} eq 'Pathomorphology';
				if ($LTB->{biomarker} eq 'pan-TRK') {
					push(@additional, encode('utf-8', 'NTRK1 (экспрессия)'));
					push(@additional, encode('utf-8', 'NTRK2 (экспрессия)'));
					push(@additional, encode('utf-8', 'NTRK3 (экспрессия)'));
					next;
					}
				push(@additional, $LTB->{LTBM});
				}
			if ($template->{TMB} > 0) {
				push(@additional, encode('utf-8', 'мутационная нагрузка'));
				}
			$goal = $goal . encode('utf-8', ', а также дополнительные маркеры: ') . join(', ', @additional) . "<br>";
			} else {
			$goal = $goal . "<br>";
			}
		$goal = $goal.encode('UTF-8', "Клиническая интерпретация выполняется в соответствии с принципами доказательной медицины следуя международным рекомендациям в области прецизионной онкологии (ESMO, ASCO) на основании собственной базы знаний, включающей международные и отечественные клинические руководства (NCCN/ASCO/ESMO/АОР), а также результаты клинических и доклинических исследований.");
		$template->{"Goal"} = $goal;
		return $template;
		}
	
	
	return $template;
	}

sub report_generate_MajorComments {
	my $class = shift;
	my $template = shift;
	
	$template->{MajorComments} = [];
	foreach my $MutationResult (sort {$a->Mutation->VariantAnnotation->Transcript->Gene->info->{genesymbol} cmp $b->Mutation->VariantAnnotation->Transcript->Gene->info->{genesymbol}}  grep {$_->toBeReported ? $_ : undef} $class->Case->mutationResults) {
		next if ($MutationResult->is_signGC eq 0);
		my $MT = $MutationResult->Mutation->name.":germline_het";
		$MT = Table::MolecularTarget->fetch($class->{DB}, $MT);
		my $VUS = 1;
		foreach my $VariantInterpretation ($MT->variantInterpretations) {
			if (lc(($VariantInterpretation->info->{interpretationresult})) =~ 'pathogenic') {$VUS = 0};
			}
		my $symbol = $MutationResult->Mutation->VariantAnnotation->Transcript->Gene->info->{genesymbol};
		my $VA = $MutationResult->Mutation->VariantAnnotation;
		my $cPos = ($VA->info->{hgvsc} ? 'c.'.$VA->info->{hgvsc} : undef);
		my $pPos = ($VA->info->{hgvsp} ? 'p.'.$VA->info->{hgvsp} : undef);
		my $variant;
		if (defined($pPos)) {
			$variant = $pPos;
			} else {
			$variant = $cPos;
			}
		my $comment;
		if ($VUS eq 1) {
			$comment = encode('UTF-8', 'В результате исследования выявлен вероятно наследственный вариант ('.$variant.') в гене '.$symbol.', который не может быть классифицирован, как патогенный или нейтральный в отношении развития наследственного онкологического синдрома (VUS вариант) (подробнее см. раздел "Результаты секвенирования"). Мы рекомендуем записаться на консультацию к медицинскому генетику с целью определения клинической значимости варианта и его потенциальной связи с развитием '.$symbol.'-ассоциированного наследственного онкологического синдрома.') unless (lc($class->Case->info->{mgttypecode}) =~ 'germline');
			$comment = encode('UTF-8', 'В результате исследования выявлен наследственный вариант ('.$variant.') в гене '.$symbol.', который не может быть классифицирован, как патогенный или нейтральный в отношении развития наследственного онкологического синдрома (VUS вариант) (подробнее см. раздел "Результаты секвенирования"). Мы рекомендуем записаться на консультацию к медицинскому генетику с целью определения клинической значимости варианта и его потенциальной связи с развитием '.$symbol.'-ассоциированного наследственного онкологического синдрома.') if (lc($class->Case->info->{mgttypecode}) =~ 'germline');
			} else {
			$comment = encode('UTF-8', 'В результате исследования выявлен вероятно наследственный патогенный вариант в гене '.$symbol.', ассоциированном с наследственным онкологическим синдромом (подробнее см. раздел "Результаты секвенирования"). В соответствии с рекомендациями ACMG (Richards et al., 2015), рекомендована валидация варианта на образце нормальной ткани референсным методом секвенирования по Сэнгеру. Правильно оценить прогноз болезни, составить программу индвидуального скрининга, а также узнать риски наследственных форм онкологии у родственников поможет врач-генетик. Мы рекомендуем записаться на консультацию.') unless (lc($class->Case->info->{mgttypecode}) =~ 'germline');
			$comment = encode('UTF-8', 'В результате исследования выявлен наследственный патогенный вариант в гене '.$symbol.', ассоциированном с наследственным онкологическим синдромом (подробнее см. раздел "Результаты секвенирования"). Правильно оценить прогноз болезни, составить программу индвидуального скрининга, а также узнать риски наследственных форм онкологии у родственников поможет врач-генетик. Мы рекомендуем записаться на консультацию.') if (lc($class->Case->info->{mgttypecode}) =~ 'germline');
			}
		push (@{$template->{MajorComments}}, $comment);
		$template->{ReferenceRaw}->{parse_doi("10.1038/gim.2015.30")} = 1;
		}
	return $template;
	}

sub report_generate_NGS_gene_list_DNA {
	my $class = shift;
	my $template = shift;

	my %list;
	my %check;
	foreach my $Barcode ($class->Case->barcodes) {
		if ((($Barcode->info->{panelcode}) ne 'NOVOPMV2')and(uc($Barcode->Panel->info->{paneltype}) ne 'DNA')) {
			next;
			}
		next unless defined $Barcode->major_AN;
		if ($Barcode->info->{panelcode} eq 'NOVOPMV2') {
			map {$list{$_} = 0} $Barcode->gene_list('DNA');
			} else {
			map {$list{$_} = 0} $Barcode->gene_list;
			}
		}
	foreach my $MutationResult (sort {$a->Mutation->VariantAnnotation->Transcript->Gene->info->{genesymbol} cmp $b->Mutation->VariantAnnotation->Transcript->Gene->info->{genesymbol}}  grep {$_->toBeReported ? $_ : undef} $class->Case->mutationResults) {
		my $symbol = $MutationResult->Mutation->VariantAnnotation->Transcript->Gene->info->{genesymbol};
		$list{$symbol} = ($list{$symbol} || 0);
		my $score = max($MutationResult->is_signTP, $MutationResult->is_signCT, $MutationResult->is_signGC);
		if ($score > $list{$symbol}) {
			print STDERR "Mutation: $symbol\t",$MutationResult->get_id,"\t",join(',', ($MutationResult->is_signTP, $MutationResult->is_signCT, $MutationResult->is_signGC)),"\n";
			$list{$symbol} = $score;
			}
		}
	foreach my $CNVResult (sort {$a->CNV->Gene->info->{genesymbol} cmp $b->CNV->Gene->info->{genesymbol}}  $class->Case->CNVResults) {
		my $symbol = $CNVResult->CNV->Gene->info->{genesymbol};
		$list{$symbol} = ($list{$symbol} || 0);
		my $score = max($CNVResult->is_signTP, $CNVResult->is_signCT);
		if ($score > $list{$symbol}) {
			print STDERR "CNV: $symbol\t",$CNVResult->get_id,"\t",join(',', ($CNVResult->is_signTP, $CNVResult->is_signCT)),"\n";
			$list{$symbol} = $score;
			}
		}
	my @check;
	foreach my $key (grep {$list{$_} > 0} keys %list) {
		my $GeneType;
		$GeneType = 'significant' if $list{$key} eq '2';
		$GeneType = 'variant_nos' if $list{$key} eq '1';
		push @check, {'GeneSelect' => $key, 'GeneType' => $GeneType};
		}
	$template->{CHECKDNA} = \@check;
	$template->{listDNA} = [sort {$a cmp $b} keys %list];
	return $template;
	}

sub report_generate_NGS_gene_list_RNA {
	my $class = shift;
	my $template = shift;
	
	my %list;
	my %check;
	foreach my $Barcode ($class->Case->barcodes) {
		if ((($Barcode->info->{panelcode}) ne 'NOVOPMV2')and(uc($Barcode->Panel->info->{paneltype}) ne 'RNA')) {
			next;
			}
		#next unless defined $Barcode->major_AN;
		if (($Barcode->info->{panelcode}) eq 'NOVOPMV2') {
			map {$list{$_} = 0} $Barcode->gene_list("RNA");
			} else {
			map {$list{$_} = 0} $Barcode->gene_list;
			}
		}
	$template->{CHECKRNA} = [];
	$template->{listRNA} = [sort {$a cmp $b} keys %list];
	return $template;
	}

sub parse_doi {
	my $doi = shift;
	my $ref;
	my $cmd = "curl -LH \"Accept: text/bibliography; style=apa\" 'http://dx.doi.org/$doi' 2> /dev/null";
	print STDERR "$cmd\n";
	my $response;
	for (my $i = 1; $i < 50; $i++) {
		$response = `$cmd`;
		chomp $response;
		if (length ($response) < 2) {
			next;
			} else {
			last;
			}
		}
	if ((lc($response) =~ /doi\snot\sfound/)or(lc($response) =~ /doi\sresolution\serror/)) {
		$ref = "Unknown doi:$doi";
		} else {
		chomp $response;
		$ref = $response;
		}
	if ($ref =~ /Resource\s+not\s+found/) {
		$ref = "Unknown doi:$doi";
		}
	print STDERR "$ref\n";
	return $ref;
	}

sub report_generate_NGS_table_SNV {
	my $class = shift;
	my $template = shift;

	my @InSignSNV;
	my @SignSNV;
	foreach my $MutationResult (sort {$a->Mutation->VariantAnnotation->Transcript->Gene->info->{genesymbol} cmp $b->Mutation->VariantAnnotation->Transcript->Gene->info->{genesymbol}}  grep {$_->toBeReported ? $_ : undef} $class->Case->mutationResults) {
		print STDERR $MutationResult->Mutation->name,"\n";
		my $VA = $MutationResult->Mutation->VariantAnnotation;
		my $Mname = uc($MutationResult->Mutation->name);
		$Mname =~ s/CHR/chr/;
		my $variant;
		$variant->{SNVGene} = $VA->Transcript->Gene->info->{genesymbol};
		if ((defined($VA->info->{exonnumber}))and(defined($VA->Transcript->info->{exoncount}))) {
			$variant->{SNVGene} = $variant->{SNVGene} . ' ('.($VA->info->{exonnumber} || '-1').'/'.
							($VA->Transcript->info->{exoncount} || '-1').')';
			}
		$variant->{gPos} = $Mname;
		$variant->{cPos} = ($VA->info->{hgvsc} ? 'c.'.$VA->info->{hgvsc} : '');
		$variant->{pPos} = ($VA->info->{hgvsp} ? 'p.'.$VA->info->{hgvsp} : '');
		$variant->{PosCoverage} = $MutationResult->info->{depth};
		$variant->{MAF} = Atlas::format_VAF($MutationResult->info->{allelefrequency})."%";
		$variant->{VariantDescr} = ($MutationResult->variantDescription || '');
		my $data = $MutationResult->Mutation->VariantAnnotation->Transcript->Gene->geneDescription_biology_select($class->info->{pathologycodepurpose});
		if (defined($data)) {
		foreach my $ref (@{$data->{"links"}}) {
				if ($ref =~ /doi:\s*(\S+)/) {
					print STDERR "  ------- HERE -------\n";
					print "$ref\n";
					$ref = parse_doi($ref);
					}
				$template->{ReferenceRaw}->{$ref} = 1;
				}
			}
		if ($MutationResult->is_signTP || $MutationResult->is_signCT || $MutationResult->is_signGC) {
			push @SignSNV, $variant;
			} else {
			#print STDERR "",$MutationResult->get_id,"\tInSign\t",join(',', ($MutationResult->is_signTP, $MutationResult->is_signCT, $MutationResult->is_signGC)),"\n";
			push @InSignSNV, $variant;
			}
		}
	$template->{InSignSNV} = [@InSignSNV];
	$template->{SignSNV} = [@SignSNV];
	return $template;
	}

sub report_generate_Pharm {
	my $class = shift;
	my $template = shift;
	
	$template->{TABLELekarstv} = [];
	my @AS;
	foreach my $RTP ($class->RTPs) {
		push @AS, (map {$_->info->{activesubstanceid}} $RTP->TreatmentScheme->activeSubstances);
		}
	@AS = uniq(@AS);
	@AS = map {Table::ActiveSubstance->fetch($class->{DB}, $_)} @AS;
	foreach my $AS (@AS) {
		my $data;
		$data->{Drug} = $AS->info->{activesubstancename};
		#next unless $data->{Drug} eq 'olaparib';
		if ((defined($AS->info->{activesubstancename_r}))and
			(length($AS->info->{activesubstancename_r}) > 1)) {
			$data->{Drug} = $AS->info->{activesubstancename_r}
				. " (" . $data->{Drug} . ")";
				}
		$data->{DrugDescr} = ($AS->drugDescription_select($class->info->{pathologycodepurpose}) ? $AS->drugDescription_select($class->info->{pathologycodepurpose})->{"desc"} : encode('utf-8', "DrugDescription"));
		my @regStatus;
		foreach my $domain (qw(FDA EMA GRLS)) {
			next unless $AS->drug_is_registered($domain, $class->info->{pathologycodepurpose});
			my $domain_name = $domain;
			$domain_name = "ГРЛС" if $domain eq 'GRLS';
			push @regStatus, $domain_name;
			}
		$data->{RegStatus} = encode('utf-8', join(" ", @regStatus));
		push @{$template->{TABLELekarstv}}, $data;
		}

	return $template;
	}

sub report_generate_NGS_table_CNV {
	my $class = shift;
	my $template = shift;

	my @InSignCNV;
	my @SignCNV;
	foreach my $CNVResult (sort {$a->CNV->Gene->info->{genesymbol} cmp $b->CNV->Gene->info->{genesymbol}}  $class->Case->CNVResults) {
		my $variant;
		$variant->{CNVGene} = $CNVResult->CNV->Gene->info->{genesymbol};
		$variant->{CNVVar} = encode('utf-8', 'делеция') if $CNVResult->CNV->info->{type} eq 'del';
		$variant->{CNVVar} = encode('utf-8', 'амплификация') if $CNVResult->CNV->info->{type} eq 'amp';
		$variant->{CNVCoverage} = $CNVResult->info->{depth};
		$variant->{CNValternation} = int(100*$CNVResult->info->{fraction})/100;
		$variant->{CNVDescription} = ($CNVResult->variantDescription || '');
		if (defined($CNVResult->CNV->Gene->geneDescription_biology_select($class->info->{pathologycodepurpose}))) {
			foreach my $ref (@{$CNVResult->CNV->Gene->geneDescription_biology_select($class->info->{pathologycodepurpose})->{links}}) {
				if ($ref =~ /doi:\s*(\S+)/) {
					$ref = parse_doi($ref);
					}
				$template->{ReferenceRaw}->{$ref} = 1;
				}
			}
		if ($CNVResult->is_signTP || $CNVResult->is_signCT) {
			push @SignCNV, $variant;
			} else {
			push @InSignCNV, $variant;
			}
		}
	my $variantDummy;
	$variantDummy->{CNVGene} = encode('utf-8', 'Не выявлены');
	$variantDummy->{CNVCoverage} = '';
	$variantDummy->{CNValternation} = '';
	$variantDummy->{CNVDescription} = '';
	if (scalar(@InSignCNV) eq 0) {
		push @InSignCNV, $variantDummy;
		}
	if (scalar(@SignCNV) eq 0) {
		push @SignCNV, $variantDummy;
		}
	$template->{InSignCNV} = [@InSignCNV];
	$template->{SignCNV} = [@SignCNV];
	return $template;
	}

sub report_generate_NGS_QC_report {
	my $class = shift;
	my $template = shift;
	
	my %panel;
	foreach my $Barcode (sort {($b->info->{dataacquisitiondate} || '0000-00-00 00:00:00') cmp ($a->info->{dataacquisitiondate} || '0000-00-00 00:00:00')} $class->Case->barcodes) {
		next unless defined $Barcode->LibraryQC;
		next unless defined $Barcode->LibraryQC->info->{result};
		next unless $Barcode->LibraryQC->info->{result} eq 'PASS';
		next unless defined $Barcode->info->{panelcode};
		next if $Barcode->info->{panelcode} eq 'NOVOPMV2';
		next if defined($panel{$Barcode->info->{panelcode}});
		$panel{$Barcode->info->{panelcode}} = $Barcode;
		}
	foreach my $Barcode (sort {($b->info->{dataacquisitiondate} || '0000-00-00 00:00:00') cmp ($a->info->{dataacquisitiondate} || '0000-00-00 00:00:00')} $class->Case->barcodes) {
		next unless defined $Barcode->info->{panelcode};
		next if defined($panel{$Barcode->info->{panelcode}});
		next if $Barcode->info->{panelcode} eq 'NOVOPMV2';
		$panel{$Barcode->info->{panelcode}} = $Barcode;
		}
	my $count_low = 0; # Count of amplicons with coverage lower 20x
	my $total_amplicons = 0; # Total count of amplicons
	my $total_exon_coverage;
	my $mutation_count = 0; #Count of mutation for TMB calculation
	my $seed = 1000 + int(rand(8999));
	my $tmp_bed = $class->{DB}->config->{data_path}->{tmpPath}."/".$class->Case->get_id."_BED$seed.bed";
	my %panel_info;
	foreach my $panel_code (keys %panel) {
		my $Barcode = $panel{$panel_code};
		next unless defined $Barcode->major_AN;
		my $QC = $Barcode->get_folder.'/QC.json';
		$QC = Atlas::file_to_json($QC);
		my $lh_file = $Barcode->major_AN->folder."/Quality.txt";
		my $cmd;
		$cmd = `grep -v "# " $lh_file | wc -l`; chomp $cmd;
		$count_low += $cmd;
		my $bed_file = $Barcode->panel_bed;
		`bedtools merge -i $bed_file > $tmp_bed.tmp`;
		my $panel_size = `awk '{s=s+\$3-\$2;print s}' $tmp_bed.tmp | tail -n1`;chomp $panel_size;
		$panel_info{$panel_code} = [$panel_size, $QC->{averageC}];
		`cat $bed_file >> $tmp_bed`;
		$cmd = `grep "chr" $bed_file | wc -l`; chomp $cmd;
		$total_amplicons += $cmd;
		#print STDERR "$total_amplicons\n";
		$mutation_count += $Barcode->major_AN->TMB_mutation_count;
		}
	
	if (scalar(keys %panel_info) > 0) {
		$template->{Coverage}	= int(sum(map {$panel_info{$_}->[0]*$panel_info{$_}->[1]} keys %panel_info)/sum(map {$panel_info{$_}->[0]} keys %panel_info)).'x';
		$template->{HighCov}    = (int(1000*(1-($count_low/$total_amplicons)))/10)."%";
		$template->{LowCov}     = encode('UTF-8', "$count_low (из $total_amplicons)");
		} else {
		$template->{Coverage} = '-1';
		$template->{HighCov}    = '100%';
		$template->{LowCov}     = encode('UTF-8', 'Нет');
		}
	#$template->{HighCov}	= (int(1000*(1-($count_low/$total_amplicons)))/10)."%";
	#$template->{LowCov}	= encode('UTF-8', "$count_low (из $total_amplicons)");
	$template->{Hotspots}	= encode('UTF-8', 'Отсутствуют');
	`sort -k1,1 -k2,2n $tmp_bed > $tmp_bed.tmp`;
	`bedtools merge -i $tmp_bed.tmp > $tmp_bed`;
	`rm $tmp_bed.tmp`;
	my $exome_bed = $class->{DB}->{global_config}->{data_path}->{exome_bed};
	my $total_region = `bedtools intersect -a $tmp_bed -b /home/aod/GENOME/hg19/ANNOTATION/wgEncodeGencodeBasicV19.exome.bed -sorted | sort -k1,1 -k2,2n | sort -u | awk '{s=s+\$3-\$2;print s}' | tail -n1`;
	chomp $total_region;
	if ($total_region > 500000) {
		$template->{TMB} = int(10*($mutation_count*1000000/$total_region))/10;
		} else {
		$template->{TMB} = "-1";
		}

	# Description Selection:
	$template->{SeqDescription} = '';

	if ($class->get_panels_analysed_string eq 'AODABCV1') {
		$template->{SeqDescription} = encode('UTF-8', "Секвенирование нового поколения (NGS) было проведено с целью определения точечных генетических вариантов, малых вставок и делеций (indel), а также протяженных амплификаций и делеций. Картирование найденных вариантов было проведено на основании геномной сборки GRCh37. Анализ проводился с помощью набора реагентов Соло-Тест ABC на платформе Ion Torrent S5. Набор реагентов обеспечивает полное покрытие кодирующей части генов BRCA1 и BRCA2, а также сайтов сплайсинга, обеспечивая 100% диагностическую чувствительность в отношении клинически-значимых генетических вариантов BRCA1 и BRCA2 (Ivanov et al., 2019). В отношении клинически-значимых генетических вариантов ATM и CHEK2 набор реагентов обеспечивает диагностическую чувствительность не менее 95%.\nВ разделе представлены все обнаруженные генетические варианты вне зависимости от доли альтернативного аллеля. Предел обнаружения генетических вариантов составляет в среднем 2%. В соответствии с международными руководствами, при принятии клинического решения не рекомендуется принимать во внимание варианты с долей 5% и менее - если такие варианты обнаружены, мы указываем их только в разделе \"Результаты секвенирования\" и не приводим рекомендации по терапии в отношении них. Также в результатах секвенирования приводятся наследственные генетические варианты, потенциально ассоциированные с развитием наследственных онкологических синдромов. Детектирование амплификаций и делеций может проводиться как для региона хромосомы (совокупности генов), так и для отдельного гена и отдельного региона гена. Ген считается амплифицированным в случае 3-кратного и более увеличения значений его покрытия по сравнению с референсными значениями для данного гена. Делеция определяется как гомозиготная, если ген не обнаруживается (с поправкой на содержание опухолевых клеток в образце).");
		$template->{ReferenceRaw}->{parse_doi("10.1093/nar/gkz775")} = 1;
		} elsif ($class->get_panels_analysed_string eq 'CHPV2') {
		$template->{SeqDescription} = encode('UTF-8', "Секвенирование нового поколения (NGS) было проведено с целью определения точечных генетических вариантов, малых вставок и делеций (indel), а также протяженных амплификаций и делеций. Картирование найденных вариантов было проведено на основании геномной сборки GRCh37. Анализ проводился с помощью набора реагентов IIonAmpliSeq Cancer Hotspot Panel v2 на платформе Ion Torrent S5.\nВ разделе представлены все обнаруженные генетические варианты вне зависимости от доли альтернативного аллеля. Предел обнаружения генетических вариантов составляет в среднем 2%. В соответствии с международными руководствами, при принятии клинического решения не рекомендуется принимать во внимание варианты с долей 5% и менее - если такие варианты обнаружены, мы указываем их только в разделе \"Результаты секвенирования\" и не приводим рекомендации по терапии в отношении них. Также в результатах секвенирования приводятся наследственные генетические варианты, потенциально ассоциированные с развитием наследственных онкологических синдромов. Детектирование амплификаций и делеций может проводится как для региона хромосомы (совокупности генов), так и для отдельного гена и отдельного региона гена. Ген считается амплифицированным в случае 3- кратного и более увеличения значений его покрытия по сравнению с референсными значениями для данного гена. Делеция определяется как гомозиготная, если ген не обнаруживается (с поправкой на содержание опухолевых клеток в образце).");
		} elsif (($class->get_panels_analysed_string =~ 'AODABCV1')and($class->get_panels_analysed_string =~ 'RCMGLYNCHV1')) {
		$template->{SeqDescription} = encode('UTF-8', "Секвенирование нового поколения (NGS) было проведено с целью определения точечных генетических вариантов, малых вставок и делеций (indel), а также протяженных амплификаций и делеций. Картирование найденных вариантов было проведено на основании геномной сборки GRCh37. Анализ проводился с помощью набора реагентов AmpliSeq Rep и Соло-Тест ABC на платформе Ion Torrent S5.\nНабор реагентов AmpliSeq Rep обеспечивает полное покрытие кодирующей части всех изоформ генов, ассоциированных с нарушением системы репарации ДНК (полный список генов см. ниже), а также сайтов сплайсинга, обеспечивая 100% диагностическую чувствительность в отношении клинически значимых генетических вариантов этих генов.\nНабор реагентов Соло-Тест ABC обеспечивает полное покрытие кодирующей части генов BRCA1 и BRCA2, а также сайтов сплайсинга, обеспечивая 100% диагностическую чувствительность в отношении клинически-значимых генетических вариантов BRCA1 и BRCA2 (Ivanov et al., 2019). В отношении клинически-значимых генетических вариантов ATM и CHEK2 набор реагентов Соло-Тест ABC обеспечивает диагностическую чувствительность не менее 95%.\nВ разделе представлены все обнаруженные генетические варианты вне зависимости от доли альтернативного аллеля. Предел обнаружения генетических вариантов составляет в среднем 2%. В соответствии с международными руководствами, при принятии клинического решения не рекомендуется принимать во внимание варианты с долей 5% и менее - если такие варианты обнаружены, мы указываем их только в разделе \"Результаты секвенирования\" и не приводим рекомендации по терапии в отношении них. Также в результатах секвенирования приводятся наследственные генетические варианты, потенциально ассоциированные с развитием наследственных онкологических синдромов. Детектирование амплификаций и делеций может проводиться как для региона хромосомы (совокупности генов), так и для отдельного гена и отдельного региона гена. Ген считается амплифицированным в случае 3-кратного и более увеличения значений его покрытия по сравнению с референсными значениями для данного гена. Делеция определяется как гомозиготная, если ген не обнаруживается (с поправкой на содержание опухолевых клеток в образце).");
		$template->{ReferenceRaw}->{parse_doi("10.1093/nar/gkz775")} = 1;
		} elsif ($class->get_panels_analysed_string eq 'AODCPV1') {
		$template->{SeqDescription} = encode('UTF-8', "Секвенирование нового поколения (NGS) было проведено с целью определения точечных генетических вариантов, малых вставок и делеций (indel), а также протяженных амплификаций и делеций. Картирование найденных вариантов было проведено на основании геномной сборки GRCh37. Анализ проводился с помощью набора реагентов Соло-тест Атлас на платформе Ion Torrent S5.\nВ разделе представлены все обнаруженные генетические варианты вне зависимости от доли альтернативного аллеля. Предел обнаружения генетических вариантов составляет в среднем 2%. В соответствии с международными руководствами, при принятии клинического решения не рекомендуется принимать во внимание варианты с долей 5% и менее - если такие варианты обнаружены, мы указываем их только в разделе \"Результаты секвенирования\" и не приводим рекомендации по терапии в отношении них. Также в результатах секвенирования приводятся наследственные генетические варианты, потенциально ассоциированные с развитием наследственных онкологических синдромов. Детектирование амплификаций и делеций может проводиться как для региона хромосомы (совокупности генов), так и для отдельного гена и отдельного региона гена. Ген считается амплифицированным в случае 3-кратного и более увеличения значений его покрытия по сравнению с референсными значениями для данного гена. Делеция определяется как гомозиготная, если ген не обнаруживается (с поправкой на содержание опухолевых клеток в образце).");
		} elsif (($class->get_panels_analysed_string =~ 'AODABCV1')and($class->get_panels_analysed_string =~ 'CCP')) {
		$template->{SeqDescription} = encode('UTF-8', "Секвенирование нового поколения (NGS) было проведено с целью определения точечных генетических вариантогенетических вариантовв, малых вставок и делеций (indel), а также протяженных амплификаций и делеций. Картирование найденных вариантов было проведено на основании геномной сборки GRCh37. Анализ проводился с помощью набора реагентов Ion AmpliSeq(TM) Comprehensive Cancer Panel и Соло-Тест ABC на платформе Ion Torrent S5.\nНабор реагентов Ion AmpliSeq(TM) Comprehensive Cancer Panel обеспечивает полное покрытие кодирующей части 409 онкогенов и генов опухолевой супрессии. Набор реагентов Соло-Тест ABC обеспечивает полное покрытие кодирующей части генов BRCA1 и BRCA2, а также сайтов сплайсинга, обеспечивая 100% диагностическую чувствительность в отношении клинически-значимых генетических вариантов BRCA1 и BRCA2 (Ivanov et al., 2019). В отношении клинически-значимых генетических вариантов ATM и CHEK2 набор реагентов Соло-Тест ABC обеспечивает диагностическую чувствительность не менее 95%.\nВ разделе представлены все обнаруженные генетические варианты вне зависимости от доли альтернативного аллеля. Предел обнаружения генетических вариантов составляет в среднем 2%. В соответствии с международными руководствами, при принятии клинического решения не рекомендуется принимать во внимание варианты с долей 5% и менее - если такие варианты обнаружены, мы указываем их только в разделе \"Результаты секвенирования\" и не приводим рекомендации по терапии в отношении них. Также в результатах секвенирования приводятся наследственные генетические варианты, потенциально ассоциированные с развитием наследственных онкологических синдромов. Детектирование амплификаций и делеций может проводиться как для региона хромосомы (совокупности генов), так и для отдельного гена и отдельного региона гена. Ген считается амплифицированным в случае 3-кратного и более увеличения значений его покрытия по сравнению с референсными значениями для данного гена. Делеция определяется как гомозиготная, если ген не обнаруживается (с поправкой на содержание опухолевых клеток в образце).\nМутационная нагрузка рассчитана как отношение количества соматических мутаций (за исключением субклональных и синонимичных замен) на общую длину целевой последовательности кодирующей ДНК (Zehir et al., 2017). Высокой мутационной нагрузкой считается значение 10 мутаций на 1 000 000 пар нуклеотидов (10 Mut/Mb) и более. Фильтрация вариантов по качеству выполнена в соответствии с рекомендациями по гармонизации расчета мутационной нагрузки (Merino et al., 2020). Высокая мутационная нагрузка может быть ассоциирована с потенциальной эффективностью иммунотерапии. При этом в оригинальных исследованиях разных иммунотерапевтических препаратов использовались разные методики расчета мутационной нагрузки. Однако исследования показывают, что при высоких значениях, результаты разных методик конкордантны (или сходятся) (Noskova, et al. 2020; Vokes et al., 2019).");
		$template->{ReferenceRaw}->{parse_doi("10.1093/nar/gkz775")} = 1;
		$template->{ReferenceRaw}->{parse_doi("10.1038/nm.4333")} = 1;
		$template->{ReferenceRaw}->{parse_doi("10.1136/jitc-2019-000147")} = 1;
		$template->{ReferenceRaw}->{parse_doi("10.1136/jitc-2019-000147")} = 1;
		$template->{ReferenceRaw}->{parse_doi("10.3390/cancers12010230")} = 1;
		$template->{ReferenceRaw}->{parse_doi("10.1200/PO.19.00171")} = 1;
		} elsif (($class->get_panels_analysed_string =~ 'OCAV3')and($class->get_panels_analysed_string =~ 'OCAV3RNA')) {
		$template->{SeqDescription} = encode('UTF-8', "Секвенирование нового поколения (NGS) ДНК, выделенной из предоставленных образцов, было проведено с целью определения точечных мутаций (SNV), малых вставок и делеций (indel), а также протяженных амплификаций и делеций (CNV). Секвенирование РНК было проведено с целью определения геномных перестроек. Картирование найденных вариантов было проведено на основании геномной сборки GRCh37. Анализ проводился с помощью набора реагентов Oncomine TM Comprehensive Assay V3 на платформе Ion Torrent S5. В разделе представлены все обнаруженные генетические варианты вне зависимости от доли альтернативного аллеля. Предел обнаружения генетических вариантов составляет в среднем 2%. В соответствии с международными руководствами, при принятии клинического решения не рекомендуется принимать во внимание варианты с долей 5% и менее - если такие варианты обнаружены, мы указываем их только в разделе \"Результаты секвенирования\" и не приводим рекомендации по терапии в отношении них. Также в результатах секвенирования приводятся наследственные генетические варианты, потенциально ассоциированные с развитием наследственных онкологических синдромов. Детектирование амплификаций и делеций может проводиться как для региона хромосомы (совокупности генов), так и для отдельного гена и отдельного региона гена. Ген считается амплифицированным в случае 3- кратного и более увеличения значений его покрытия по сравнению с референсными значениями для данного гена. Делеция определяется как гомозиготная, если ген не обнаруживается (с поправкой на содержание опухолевых клеток в образце).");
		} elsif ($class->get_panels_analysed_string eq 'NOVOPMV2') {
		$template->{SeqDescription} = encode('UTF-8', "Секвенирование нового поколения (NGS) ДНК, выделенной из предоставленных образцов, было проведено с целью определения точечных мутаций (SNV), малых вставок и делеций (indel), а также протяженных амплификаций и делеций (CNV). Картирование найденных вариантов было проведено на основании геномной сборки GRCh37. Анализ проводился с помощью набора реагентов NovoGene NovoPM 2.0 TM с использованием технологии sequencing by synthesis (Illumina). В разделе представлены все обнаруженные генетические варианты вне зависимости от доли альтернативного аллеля. Предел обнаружения генетических вариантов составляет в среднем 2%. В соответствии с международными руководствами, при принятии клинического решения не рекомендуется принимать во внимание варианты с долей 5% и менее - если такие варианты обнаружены, мы указываем их только в разделе \"Результаты секвенирования\" и не приводим рекомендации по терапии в отношении них. Также в результатах секвенирования приводятся наследственные генетические варианты, потенциально ассоциированные с развитием наследственных онкологических синдромов. Детектирование амплификаций и делеций может проводиться как для региона хромосомы (совокупности генов), так и для отдельного гена и отдельного региона гена. Ген считается амплифицированным в случае 3- кратного и более увеличения значений его покрытия по сравнению с референсными значениями для данного гена. Делеция определяется как гомозиготная, если ген не обнаруживается (с поправкой на содержание опухолевых клеток в образце).\nМутационная нагрузка рассчитана как отношение количества соматических мутаций (за исключением субклональных и синонимичных замен) на общую длину целевой последовательности кодирующей ДНК (Zehir et al., 2017). Высокой мутационной нагрузкой считается значение 10 мутаций на 1 000 000 пар нуклеотидов (10 Mut/Mb) и более. Фильтрация вариантов по качеству выполнена в соответствии с рекомендациями по гармонизации расчета мутационной нагрузки (Merino et al., 2020). Высокая мутационная нагрузка может быть ассоциирована с потенциальной эффективностью иммунотерапии. При этом в оригинальных исследованиях разных иммунотерапевтических препаратов использовались разные методики расчета мутационной нагрузки. Однако исследования показывают, что при высоких значениях, результаты разных методик конкордантны (или сходятся) (Noskova, et al. 2020; Vokes et al., 2019).");
                $template->{ReferenceRaw}->{parse_doi("10.1038/nm.4333")} = 1;
                $template->{ReferenceRaw}->{parse_doi("10.1136/jitc-2019-000147")} = 1;
                $template->{ReferenceRaw}->{parse_doi("10.1136/jitc-2019-000147")} = 1;
                $template->{ReferenceRaw}->{parse_doi("10.3390/cancers12010230")} = 1;
                $template->{ReferenceRaw}->{parse_doi("10.1200/PO.19.00171")} = 1;
		} else {
		$template->{SeqDescription} = encode('UTF-8', "Секвенирование нового поколения (NGS) было проведено с целью определения точечных генетических вариантогенетических вариантовв, малых вставок и делеций (indel), а также протяженных амплификаций и делеций. Картирование найденных вариантов было проведено на основании геномной сборки GRCh37. Анализ проводился с помощью набора реагентов Ion AmpliSeq(TM) Comprehensive Cancer Panel на платформе Ion Torrent S5.\nВ разделе представлены все обнаруженные генетические варианты вне зависимости от доли альтернативного аллеля. Предел обнаружения генетических вариантов составляет в среднем 2%. В соответствии с международными руководствами, при принятии клинического решения не рекомендуется принимать во внимание варианты с долей 5% и менее - если такие варианты обнаружены, мы указываем их только в разделе \"Результаты секвенирования\" и не приводим рекомендации по терапии в отношении них. Также в результатах секвенирования приводятся наследственные генетические варианты, потенциально ассоциированные с развитием наследственных онкологических синдромов. Детектирование амплификаций и делеций может проводиться как для региона хромосомы (совокупности генов), так и для отдельного гена и отдельного региона гена. Ген считается амплифицированным в случае 3-кратного и более увеличения значений его покрытия по сравнению с референсными значениями для данного гена. Делеция определяется как гомозиготная, если ген не обнаруживается (с поправкой на содержание опухолевых клеток в образце).\nМутационная нагрузка рассчитана как отношение количества соматических мутаций (за исключением субклональных и синонимичных замен) на общую длину целевой последовательности кодирующей ДНК (Zehir et al., 2017). Высокой мутационной нагрузкой считается значение 10 мутаций на 1 000 000 пар нуклеотидов (10 Mut/Mb) и более. Фильтрация вариантов по качеству выполнена в соответствии с рекомендациями по гармонизации расчета мутационной нагрузки (Merino et al., 2020). Высокая мутационная нагрузка может быть ассоциирована с потенциальной эффективностью иммунотерапии. При этом в оригинальных исследованиях разных иммунотерапевтических препаратов использовались разные методики расчета мутационной нагрузки. Однако исследования показывают, что при высоких значениях, результаты разных методик конкордантны (или сходятся) (Noskova, et al. 2020; Vokes et al., 2019).");
		$template->{ReferenceRaw}->{parse_doi("10.1038/nm.4333")} = 1;
		$template->{ReferenceRaw}->{parse_doi("10.1136/jitc-2019-000147")} = 1;
		$template->{ReferenceRaw}->{parse_doi("10.3390/cancers12010230")} = 1;
		$template->{ReferenceRaw}->{parse_doi("10.1200/PO.19.00171")} = 1;
		}

	return $template;
	}

sub a_mean {
	return sum(@_)/@_;
	}

sub report_generate_pathomorphology_results {
	my $class = shift;
	my $template = shift;
	
	delete $template->{PathDiagnosis};
	my $PRoute = $class->Case->PRoute->info->{filekey};
	my $data = Atlas::wrap_python("python $local_path/../../scripts/python/SS_read_Pathomorphology.py $PRoute");
	chomp $data;
	$data = 'NA' if (uc($data)) eq 'N/A';
	$data = 'NA' if (uc($data)) eq 'N\A';
	$data = 'NA' if (uc($data)) eq 'NA';

	if ((length($data) < 1)or($data eq 'NA')) {
		} else {
		$template->{PathDiagnosis} = $data;
		}
	$template->{Path} = [];
	if ((length($data) < 1)) {
		} else {
		my $result;
		$result->{"PathQ"} = [];
		$result->{"PathC"} = "Enter Text Here";
		$result->{"MacrC"} = "Enter Text Here";
		$result->{"MicrC"} = "Enter Text Here";
		$result->{"PathContractor"} = "Enter Text Here";
		push (@{$template->{Path}}, $result);
		}
	return $template;
	}

sub get_PRoute_data {
	my $class	= shift;
	return undef unless defined $class->Case->PRoute;
	my $PRoute = $class->Case->PRoute->info->{filekey};
	my $template = $class->Case->PRoute->info->{templateversion};
	
	$template = $class->{DB}->config->{drive}->{files}->{requisition_template}->{$template}->{key};
	my $data = Atlas::wrap_python("python $local_path/../../scripts/python/SS_read_PRoute.py $PRoute $template");
	$data = [split/\n/, $data];
	$class->info->{PRoute_data} = $data;
	$class->parse_PRoute_data;
	}

sub check_PRoute_data {
	my $class	= shift;
	my $data;

	if (defined($class->info->{PRoute_data})) {
		$data = $class->info->{PRoute_data};
		} else {
		$data = $class->get_PRoute_data;
		}
	foreach my $Result (@{$class->info->{PRoute_data}}) {
		if (uc($Result->{LTRes}) eq 'NOT COMPLETE') {
			$class->{error} = 'Файл с направлением (https://docs.google.com/spreadsheets/d/'.$class->Case->PRoute->info->{filekey}.') не заполнен - заполните результаты всех проведенных тестов, для которых указан приоритет (помимо NGS) или укажите, что тест в итоге не выполнен';
			return 1;
			}
		}
	return 0;
	}

sub parse_PRoute_data {
	my $class	= shift;
	my $data = $class->info->{PRoute_data};
	my $PRoute_parsed = [];
	my $PRoute_parsed_inProgress = [];
	my $PRoute_parsed_canceled = [];
	my $i = 0;
	while (1) {
		last unless defined $data->[7*$i+6];
		my @LTRes;
		my @LBTM;
		my @biomarker;

		if ($data->[7*$i+2] eq 'Pathomorphology') {
			@LTRes = ($data->[7*$i+6]);
			@LBTM  = ($data->[7*$i]);
			@biomarker = ($data->[7*$i+2]);
			} else {
			@LTRes = split/\//, $data->[7*$i+6];
			@LBTM  = split/\//, $data->[7*$i];
			@biomarker = split/\//, $data->[7*$i+2];
			}
		for (my $ResIndex = 0; $ResIndex < scalar @LTRes; ++$ResIndex) {
			next if uc($LTRes[$ResIndex]) eq 'CANCELED';
			next if uc($LTRes[$ResIndex]) =~ 'PROGRES';
			next if uc($LTRes[$ResIndex]) =~ 'WAIT';
			my $result;
			$result->{LTBM}   = $LBTM[$ResIndex];
			$result->{LTRes}  = $LTRes[$ResIndex];
			$result->{LTMethod} = $data->[7*$i+1];
			$result->{LTProof}  = 'N';
			$result->{biomarker}  = $biomarker[$ResIndex];
			$result->{change_eng}  = $data->[7*$i+3];
			$result->{change_rus}  = $data->[7*$i+4];
			$result->{change_rus_genitive}  = $data->[7*$i+5];
			if (uc($LTRes[$ResIndex]) =~ 'CANCELED') {
				push @{$PRoute_parsed_canceled}, $result;
				} elsif (uc($LTRes[$ResIndex]) =~ 'PROGRES') {
				push @{$PRoute_parsed_inProgress}, $result;
				} elsif (uc($LTRes[$ResIndex]) =~ 'WAIT') {
				push @{$PRoute_parsed_inProgress}, $result;
				} else {
				push @{$PRoute_parsed}, $result;
				}
			}
		++$i;
		}
	$class->info->{PRoute_data} = $PRoute_parsed;
	$class->info->{PRoute_data_inProgress} = $PRoute_parsed_inProgress;
	$class->info->{PRoute_data_canceled} = $PRoute_parsed_canceled;
	}

sub report_generate_LTResults {
	my $class	= shift;
	my $template	= shift;
	my @LTResults;
	
	$template->{"LTResults"} = [];
	## Заполняем сделанные аналоговые тесты - из направления
	
	$class->get_PRoute_data unless defined($class->info->{PRoute_data});
	#print STDERR Dumper $class->info->{PRoute_data};
	if ($class->check_PRoute_data eq 0) {
		my $i = 0;
		my $data = $class->info->{PRoute_data};
		foreach my $Result (@{$class->info->{PRoute_data}}) {
			next if $Result->{LTBM} eq 'Pathomorphology';
			if ((uc($Result->{biomarker}) eq 'PAN-TRK')and(decode('utf-8', $Result->{LTRes}) =~ /триц/)) {
				for (my $i = 1; $i <= 3; $i++) {
					my $result;
					$result->{LTBM}         = encode('utf-8', "NTRK$i (экспрессия)");
					$result->{LTRes}        = $Result->{LTRes};
					$result->{LTMethod}     = $Result->{LTMethod};
					$result->{LTProof}      = 'N';
					push @{$template->{"LTResults"}} ,$result;
					}
				} else {
				my $result;
				$result->{LTBM}		= $Result->{LTBM};
				$result->{LTRes}	= $Result->{LTRes};
				$result->{LTMethod}	= $Result->{LTMethod};
				$result->{LTProof}	= 'N';
				push @{$template->{"LTResults"}} ,$result;
				}
			}
		foreach my $Result (@{$class->info->{PRoute_data_inProgress}}) {
			my $result;
			$result->{LTBM}         = $Result->{LTBM};
			$result->{LTRes}        = encode('utf-8', 'Нет данных*');
			$result->{LTMethod}	= '';
			$result->{LTProof}	= 'N';
			push @{$template->{"LTResults"}} ,$result;
			$template->{"Disclaimer"} = {} unless (defined($template->{"Disclaimer"}));
			$template->{"Disclaimer"}->{LTR_IN_PROGRESS} = encode('utf-8', "* Исследование в процессе");
			}
		}
	## Заполняем мутационную нагрузку
	
	if (defined($template->{TMB})) {
		} else {
		$template = $class->report_evaluate_TMB($template);
		}
	if ($template->{TMB} > 0) {
		my $result;
		$result->{LTMethod} = encode('UTF-8', 'NGS');
		$result->{LTBM} = encode('UTF-8', 'Мутационная нагрузка');
		if ($template->{TMB} > 10) {
			$result->{LTRes} = encode('UTF-8', 'Высокая ('.$template->{TMB}.' Мут/Мб)');
			} else {
			$result->{LTRes} = encode('UTF-8', 'Низкая ('.$template->{TMB}.' Мут/Мб)');
			}
		push @{$template->{"LTResults"}}, $result;
		}

	## Заполняем обнаруженны мутации
	my $biomarker_list_Folder = $class->{DB}->{global_config}->{data_path}->{configPath};
	$biomarker_list_Folder = $biomarker_list_Folder . "/biomarker_list";
	opendir (my $BIOMARKER_LIST, "$biomarker_list_Folder");
	
	my $min_distance = 99;
	my $min_distance_file = 'CANCER';
	my $pathology_purpose = $class->info->{pathologycodepurpose};
	$pathology_purpose = 'cancer' unless defined $pathology_purpose;
	print STDERR "PathologyCodePurpose - $pathology_purpose\n";
	die "Unknown PathologyCodePurpose\n" unless defined $pathology_purpose;
	my $Pathology = $class->{DB}->Pathology($pathology_purpose);
	while (my $file_name = readdir($BIOMARKER_LIST)) {
		next if $file_name eq '.';
		next if $file_name eq '..';
		next if $Pathology->find_distance_up($file_name) eq '-1';
		if ($Pathology->find_distance_up($file_name) < $min_distance) {
			$min_distance = $Pathology->find_distance_up($file_name);
			$min_distance_file = $biomarker_list_Folder . '/' . $file_name;
			}
		}
	
	print STDERR "$min_distance_file\n";
	
	open (REPORT_GENERATE_LTRESULTS, "<$min_distance_file");
	
	my @gene_list = $class->get_gene_list;
	my %LTR_genes_SNV;
	my %LTR_genes_CNV;
	while (<REPORT_GENERATE_LTRESULTS>) {
		my $line = $_;
		chomp $line;
		next if $line =~ /!#/;
		$line = [split/\t/,$line];
		next unless $line->[0] ~~ @gene_list;
		my $result;
		$result->{LTMethod} = encode('UTF-8', 'NGS');
		$result->{LTRes} = encode('UTF-8', 'отрицательный');
		if ($line->[3] eq 'mut') {
			$result->{LTBM} = encode('UTF-8', $line->[0].' (ген. варианты)');
			my @res;
			foreach my $MR ($class->Case->mutationResults) {
				next unless defined $MR->Mutation->VariantAnnotation;
				next unless defined $MR->Mutation->VariantAnnotation->Transcript;
		
				next if (lc($MR->Mutation->VariantAnnotation->Transcript->Gene->info->{genesymbol}) ne lc($line->[0]));
				next if ($MR->is_signCT + $MR->is_signTP + $MR->is_signGC) eq 0;
				push @res, $MR->Mutation->HGVS_name;
				}
			if (scalar @res > 0) {
				$result->{LTRes} = join(',', @res);
				}
			$LTR_genes_SNV{uc($line->[0])} = 1;
			}
		if ($line->[3] eq 'CNVamp') {
			$result->{LTBM} = encode('UTF-8', $line->[0].' (амплификация гена)');
			foreach my $CNVR ($class->Case->CNVResults) {
				next if $CNVR->CNV->info->{type} ne 'amp';
				next if (lc($CNVR->CNV->Gene->info->{genesymbol}) ne lc($line->[0]));
				next if ($CNVR->is_signCT + $CNVR->is_signTP) eq 0;
				$result->{LTRes} = encode('utf-8', 'положительный');
				}
			$LTR_genes_CNV{lc($line->[0])} = 1;
			}
		if ($line->[3] eq 'CNVdel') {
			$result->{LTBM} = encode('UTF-8', $line->[0].' (делеция гена)');
			foreach my $CNVR ($class->Case->CNVResults) {
				next if $CNVR->CNV->info->{type} ne 'del';
				next if (lc($CNVR->CNV->Gene->info->{genesymbol}) ne lc($line->[0]));
				next if ($CNVR->is_signCT + $CNVR->is_signTP) eq 0;
				$result->{LTRes} = encode('utf-8', 'положительный');
				}
			$LTR_genes_CNV{uc($line->[0])} = 1;
			}
		push @{$template->{"LTResults"}}, $result;
		}
	
	close REPORT_GENERATE_LTRESULTS;
	
	foreach my $MR ($class->Case->mutationResults) {
		next unless defined $MR->Mutation->VariantAnnotation;
		next unless defined $MR->Mutation->VariantAnnotation->Transcript;
		next if ($MR->is_signCT + $MR->is_signTP + $MR->is_signGC) eq 0;
		next if $LTR_genes_SNV{uc($MR->Mutation->VariantAnnotation->Transcript->Gene->info->{genesymbol})};
		my $result;
		$result->{LTMethod} = encode('UTF-8', 'NGS');
		$result->{LTBM} = encode('UTF-8', $MR->Mutation->VariantAnnotation->Transcript->Gene->info->{genesymbol}.' (ген. варианты)');
		my @res;
		foreach my $MR_inner ($class->Case->mutationResults) {
			next unless defined $MR_inner->Mutation->VariantAnnotation;
			next unless defined $MR_inner->Mutation->VariantAnnotation->Transcript;
			next if (lc($MR_inner->Mutation->VariantAnnotation->Transcript->Gene->info->{genesymbol}) ne 
				lc($MR->Mutation->VariantAnnotation->Transcript->Gene->info->{genesymbol}));
			next if ($MR_inner->is_signCT + $MR_inner->is_signTP + $MR_inner->is_signGC) eq 0;
			push @res, $MR_inner->Mutation->HGVS_name;
			$LTR_genes_SNV{lc($MR_inner->Mutation->VariantAnnotation->Transcript->Gene->info->{genesymbol})} = 1;
			}
		next if scalar @res < 1;
		$result->{LTRes} = join(',', @res);
		push @{$template->{"LTResults"}}, $result;
		}
	
	foreach my $CNVR ($class->Case->CNVResults) {
		next if ($CNVR->is_signCT + $CNVR->is_signTP) eq 0;
		next if $LTR_genes_CNV{uc($CNVR->CNV->Gene->info->{genesymbol})};
		my $result;
		$result->{LTMethod} = encode('UTF-8', 'NGS');
		$result->{LTBM} = encode('UTF-8', $CNVR->CNV->Gene->info->{genesymbol}.' (амплификация)') if $CNVR->CNV->info->{type} eq 'amp';
		$result->{LTBM} = encode('UTF-8', $CNVR->CNV->Gene->info->{genesymbol}.' (делеция)') if $CNVR->CNV->info->{type} eq 'del';
		$result->{LTRes} = encode('utf-8', 'положительный');
		push @{$template->{"LTResults"}}, $result;
		}
	
	$template->{"LTResults"} = [sort {$a->{LTMethod} cmp $b->{LTMethod} || $a->{LTBM} cmp $b->{LTBM}} @{$template->{"LTResults"}}];
	my @finalLTR;
	for (my $i = 0; $i < scalar @{$template->{"LTResults"}}; $i++) {
		if (defined($finalLTR[$i-1])) {
			#print STDERR $template->{"LTResults"}->[$i]->{LTBM},"\t",$finalLTR[$i-1]->{LTBM},"\n";
			#print STDERR $template->{"LTResults"}->[$i]->{LTMethod},"\t",$finalLTR[$i-1]->{LTMethod},"\n";
			#print STDERR $template->{"LTResults"}->[$i]->{LTRes},"\t",$finalLTR[$i-1]->{LTRes},"\n";
			if (($template->{"LTResults"}->[$i]->{LTBM} eq $finalLTR[$i-1]->{LTBM})and
		       		($template->{"LTResults"}->[$i]->{LTMethod} eq $finalLTR[$i-1]->{LTMethod})and
				($template->{"LTResults"}->[$i]->{LTRes} eq $finalLTR[$i-1]->{LTRes})) {
				#print STDERR "HERE\n";
				next;
				}
			}
		push @finalLTR, $template->{"LTResults"}->[$i];
		}
	$template->{"LTResults"} = [@finalLTR];
	closedir $BIOMARKER_LIST;
	return $template;
	}

sub uniq {
    my %seen;
    grep !$seen{$_}++, @_;
}	

sub report_prepare_template {
	my $class = shift;
	my $template = $class->{DB}->{global_config}->{data_path}->{configPath};
	$template = "$template/pdf_source/results.json";
	$template = Atlas::file_to_json($template);
	#delete $template->{TABLECli};
	#delete $template->{PBT};
	#delete $template->{LOBT};
	#delete $template->{ToxT};
	#delete $template->{Disclaimer3};
	#delete $template->{LTResults};
	#delete $template->{ALTResults};
	#delete $template->{TABLE};
	#delete $template->{TABLELekarstv};
	#delete $template->{CHECK};
	#delete $template->{list};
	#delete $template->{SignSNV};
	#delete $template->{InSignSNV};
	#delete $template->{SignCNV};
	#delete $template->{InSignCNV};
	#delete $template->{Path};
	#delete $template->{IGH};
	#delete $template->{FISH};
	#delete $template->{MSI};
	delete $template->{Info};
	#delete $template->{Reference};
	$template->{Reference} = [];
	$template->{ReferenceRaw} = {};
	delete $template->{GPanel};
	#delete $template->{list};
	return $template;
	}

sub report_generate_file_name {
	my $class = shift;
	
	my $seed = 1000 + int(rand(8999));
	my $reportFile = $class->{DB}->config->{data_path}->{tmpPath}."/";
	$reportFile = $reportFile.$class->Case->get_id."_AUTO$seed";
	return $reportFile;
	}















	
	
	
	
	
	
	
	
	
	
	
	
	
	
1;
