
package YapRI::Base;

use strict;
use warnings;
use autodie;

use Carp qw( carp croak cluck );
use Math::BigFloat;
use File::Temp qw( tempfile tempdir );
use File::Path qw( make_path remove_tree);
use File::stat;

## To export some functions

use Exporter qw( import );

our @EXPORT_OK = qw( r_var );

###############
### PERLDOC ###
###############

=head1 NAME

YapRI::Base.pm
A wrapper to interact with R/

=cut

our $VERSION = '0.01';
$VERSION = eval $VERSION;

=head1 SYNOPSIS

  use YapRI::Base;

  ## WORKING WITH THE DEFAULT MODE:

  my $rih = YapRI::Base->new();
  $rih->add_command('bmp(filename="myfile.bmp", width=600, height=800)');
  $rih->add_command('dev.list()');
  $rih->add_command('plot(c(1, 5, 10), type = "l")');
  $rih->add_command('dev.off()');
 
  $rih->run_command();
  
  my $result_file = $rih->get_resultfiles('default');



  ## WORKING WITH COMMAND BLOCKS:

  my $rih = YapRI::Base->new();

  ## Create a file-block_1

  $rih->create_block('BLOCK1');
  $rih->add_command('x <- c(10, 9, 8, 5)', 'BLOCK1');
  $rih->add_command('z <- c(12, 8, 8, 4)', 'BLOCK1');
  $rih->add_command('x + z', 'BLOCK1')
  
  ## Create a file-block_2

  $rih->create_block('BLOCK2');   
  $rih->add_command('bmp(filename="myfile.bmp", width=600, height=800)', 
                    'BLOCK2');
  $rih->add_command('dev.list()', 'BLOCK2');
  $rih->add_command('plot(c(1, 5, 10), type = "l")', 'BLOCK2');
  
  ## Run each block

  $rih->run_block('BLOCK1');
  $rih->run_block('BLOCK2');

  ## Get the results

   my $resultfile1 = $rih->get_resultfiles('BLOCK1');
   my $resultfile2 = $rih->get_resultfiles('BLOCK2');

  ## Combine block before run it

   $rih->combine_blocks(['BLOCK1', 'BLOCK2'], 'NEWBLOCK');
   $rih->run_block('NEWBLOCK');



=head1 DESCRIPTION

 Another yet perl wrapper to interact with R


=head1 AUTHOR

Aureliano Bombarely <ab782@cornell.edu>


=head1 CLASS METHODS

The following class methods are implemented:

=cut 



############################
### GENERAL CONSTRUCTORS ###
############################

=head1 (*) CONSTRUCTORS:

=head2 ---------------


=head2 constructor new

  Usage: my $rih = YapRI::Base->new($arguments_href);

  Desc: Create a new R interfase object.

  Ret: a YapRI::Base object

  Args: A hash reference with the following parameters:
        cmddir       => A string, a dir to store the command files
        cmdfiles     => A hash ref. with pair key=alias, value=filename
        r_opts_pass  => A string with the R options passed to run_command
        use_defaults => 0|No to disable the default values.
        
  Side_Effects: Die if the argument used is not a hash or its values arent 
                right.
                By default it will use set_default_cmddir(), 
                add_default_cmdfile() and set_default_r_opts_pass();

  Example: ## Default method:
              my $rih = YapRI::Base->new();
          
           ## Create an empty object
              my $rih = YapRI::Base->new({ use_defaults => 0 });

           ## Defining own dir and command file
              
              my $rcmd_file = '/home/user/R/myRfile.txt';
              open my $rfh, '>', $rcmd_file;
              my $rih = YapRI::Base->new({ 
                                            cmddir   => '/home/user/R',
                                            cmdfiles => { $rcmd_file => $rfh },
                                         });

=cut

sub new {
    my $class = shift;
    my $args_href = shift;

    my $self = bless( {}, $class ); 

    my %permargs = (
	cmddir       => '\w+',
	cmdfiles     => {},
	r_opts_pass  => '-{1,2}\w+',
	use_defaults => '0|1|no|yes|',
	);

    ## Check variables.

    my %args = ();
    if (defined $args_href) {
	unless (ref($args_href) eq 'HASH') {
	    croak("ARGUMENT ERROR: Arg. supplied to new() isnt HASHREF");
	}
	else {
	    %args = %{$args_href}
	}
    }

    foreach my $arg (keys %args) {
	unless (exists $permargs{$arg}) {
	    croak("ARGUMENT ERROR: $arg isnt permited arg for new() function");
	}
	else {
	    unless (defined $args{$arg}) {
		croak("ARGUMENT ERROR: value for $arg isnt defined for new()");
	    }
	    else {
		if (ref($permargs{$arg})) {
		    unless (ref($permargs{$arg}) eq ref($args{$arg})) {
			croak("ARGUMENT ERROR: $args{$arg} isnt permited val.");
		    }
		}
		else {
		    if ($args{$arg} !~ m/$permargs{$arg}/) {
			croak("ARGUMENT ERROR: $args{$arg} isnt permited val.");
		    }
		}
	    }
	}
    }

    my $defs = 1;
    if (defined $args{use_defaults}) {
	$defs = $args{use_defaults};
    }

    ## Set the dir to put all the commands

    my $cmddir = $args{cmddir} || '';  ## Empty var by default
    $self->set_cmddir($cmddir);
    if ($defs =~ m/^[1|yes]$/i) {
	$self->set_default_cmddir();
    }

    my $cmdfiles_href = $args{cmdfiles} || {}; ## Empty hashref by default  
    $self->set_cmdfiles($cmdfiles_href);
    if ($defs =~ m/^[1|yes]$/i) {
	$self->add_default_cmdfile();
    }

    my $resfiles_href = $args{resultfiles} || {}; ## Empty hashref by default  
    $self->set_resultfiles($resfiles_href);

    my $r_optspass = $args{r_opts_pass} || '';  ## Empty scalar by default 
    if ($defs =~ m/^[1|yes]$/i) {
	$self->set_default_r_opts_pass();
    }
    else {
	$self->set_r_opts_pass($r_optspass);
    }

    return $self;
}

=head2 cleanup

  Usage: my $deleted_data_href = $rih->cleanup();

  Desc: Close all the filehandles and remove the cmddir with all the files

  Ret: A hash reference with key=datatype and value=datadeleted
       keys = cmddir and cmdfiles; 

  Args: None        
        
  Side_Effects: None

  Example: $rih->cleanup();

=cut

sub cleanup {
    my $self = shift;

    ## First delete the files and remove the file hash from the object

    my %cmdfiles = %{$self->get_cmdfiles()};
    foreach my $alias (keys %cmdfiles) {
	$self->delete_cmdfile($alias); 
    }
    
    $self->set_cmdfiles({});

    ## Remove the cmddir with all the files and the cmddir from the object

    my $cmddir = $self->delete_cmddir();

    return ( { cmddir => $cmddir, cmdfiles => \%cmdfiles} );
}



#################
### ACCESSORS ###
#################

=head1 (*) ACCESSORS:

=head2 ------------

=head2 get_cmddir

  Usage: my $cmddir = $rih->get_cmddir(); 

  Desc: Get the command dir used by the r interfase object

  Ret: $cmddir, a scalar

  Args: None

  Side_Effects: None

  Example: my $cmddir = $rih->get_cmddir();   

=cut

sub get_cmddir {
    my $self = shift;
    return $self->{cmddir};
}

=head2 set_cmddir

  Usage: $rih->set_cmddir($cmddir); 

  Desc: Set the command dir used by the r interfase object

  Ret: None

  Args: $cmddir, a scalar

  Side_Effects: Die if no argument is used.
                Die if the cmddir doesnt exists

  Example: $rih->set_cmddir($cmddir); 

=cut

sub set_cmddir {
    my $self = shift;
    my $cmddir = shift;
 
    unless (defined $cmddir) {
	croak("ERROR: cmddir argument used for set_cmddir function is undef.");
    }
    else {
	if ($cmddir =~ m/\w+/) {  ## If there are something check if exists
	    unless (defined(-f $cmddir)) {
		croak("ERROR: dir arg. used for set_cmddir() doesnt exists");
	    }
	}
    }
    
    $self->{cmddir} = $cmddir;
}

=head2 set_default_cmddir

  Usage: $rih->set_default_cmddir(); 

  Desc: Set the command dir used by the r interfase object with a default value
        such as RiPerldir_XXXXXXXX

  Ret: None

  Args: None

  Side_Effects: Create the perl_ri_XXXXXXXX folder in the tmp dir

  Example: $rih->set_default_cmddir(); 

=cut

sub set_default_cmddir {
    my $self = shift;

    my $cmddir = tempdir('RiPerldir_XXXXXXXX', TMPDIR => 1);

    $self->{cmddir} = $cmddir;
}


=head2 delete_cmddir

  Usage: my $cmddir = $rih->delete_cmddir(); 

  Desc: Delete the command dir used by the r interfase object

  Ret: $cmddir, deleted cmddir

  Args: None

  Side_Effects: Die if no argument is used.

  Example: $rih->delete_cmddir(); 

=cut

sub delete_cmddir {
    my $self = shift;

    my $cmddir = $self->get_cmddir();
    remove_tree($cmddir);
    
    delete($self->{cmddir});

    ## Set an empty variable
    $self->set_cmddir('');

    return $cmddir;
}

=head2 get_cmdfiles

  Usage: my $cmdfiles_href = $rih->get_cmdfiles(); 

  Desc: Get the command files used by the r interfase object

  Ret: $filesdir_href, a hash reference with key=alias and value=filename

  Args: $alias [optional]

  Side_Effects: None

  Example: my %cmdfiles = %{$rih->get_cmdfiles()};
           my $block1_file = $rih->get_cmdfiles('block1');

=cut

sub get_cmdfiles {
    my $self = shift;
    my $alias = shift;

    if (defined $alias) {
	return $self->{cmdfiles}->{$alias};
    }
    else { 
	return $self->{cmdfiles};
    }
}

=head2 get_default_cmdfile

  Usage: my $filename = $rih->get_default_cmdfile(); 

  Desc: Get the command default file used by the r interfase object

  Ret: $filename, default filename

  Args: None

  Side_Effects: None

  Example: my $filename = $rih->get_default_cmdfile(); 

=cut

sub get_default_cmdfile {
    my $self = shift;
    
    return $self->get_cmdfiles('default');
}


=head2 set_cmdfiles

  Usage: $rih->set_cmdfiles($cmdfiles_href); 

  Desc: Set the command files used by the r interfase object

  Ret: None

  Args: $cmdfile_hashref, an hash reference with key=alias and value=filename

  Side_Effects: Die if no argument is used.
                Die if the argument is not a hash reference
                Die if the value is not a filehandle

  Example: $rih->set_cmdfiles($cmdfiles_href); 

=cut

sub set_cmdfiles {
    my $self = shift;
    my $cmdfiles_href = shift ||
	croak("ERROR: No argument was used for set_cmdfiles function");

    unless(ref($cmdfiles_href) eq 'HASH') {
	croak("ERROR: cmdfiles arg. used for set_cmdfiles isnt a hashref.");
    }
    else {
	foreach my $alias (keys %{$cmdfiles_href}) {
	    
	    my $filename = $cmdfiles_href->{$alias};
	    unless (-f $filename) {
		croak("ERROR: cmdfiles value=$filename doesnt exist");
	    }
	}
    }
    $self->{cmdfiles} = $cmdfiles_href;
}


=head2 add_cmdfile

  Usage: $rih->add_cmdfile($alias, $filename); 

  Desc: Add a new the command file for the r interfase object

  Ret: None

  Args: $alias, a scalar
        $filename, a scalar [optional]

  Side_Effects: Die if no argument is used.
                Die if the filename supplied doesnt exist.
                Die if the alias used exist in the object
                Create a file in the cmddir if the $filename isnt supplied

  Example: $rih->add_cmdfile('block1', '/home/user/R/block1.txt');
           $rih->add_cmdfile('block1'); 

=cut

sub add_cmdfile {
    my $self = shift;
    my $alias = shift ||
	croak("ERROR: No alias argument was used for add_cmdfile function");
    
    my $filename = shift;
    
    if (exists $self->{cmdfiles}->{$alias}) {
	croak("ERROR: alias=$alias exists into $self, add_cmdfile failed");
    }

    if (defined $filename) {
	unless (-f $filename) {
	    croak("ERROR: cmdfile=$filename doesnt exist");
	}
    }
    else {
	my $cmddir = $self->get_cmddir();
	unless ($cmddir =~ m/\w+/) {
	    croak("ERROR: new cmdfile cant be created if cmddir isnt set");
	}
	(my $fh, $filename) = tempfile("RiPerlcmd_XXXXXXXX", DIR => $cmddir);
	close($fh);
    }
    
    
    $self->{cmdfiles}->{$alias} = $filename;
}

=head2 add_default_cmdfile

  Usage: $rih->add_default_cmdfile(); 

  Desc: Add a default the command file for the r interfase object

  Ret: None

  Args: None

  Side_Effects: Create a RiPerlcmd_XXXXXXXX file in the cmddir folder and
                it will open a new filehandle.
                If exists a default cmdfile in this object, it will not create 
                a new filename/fh pair

  Example: $rih->add_default_cmdfile();

=cut

sub add_default_cmdfile {
    my $self = shift;

    ## First, check there are any default file

    my $filename = $self->get_default_cmdfile();

    ## Second create a default file

    unless (defined $filename) {
	
	my $cmddir = $self->get_cmddir();
	unless ($cmddir =~ m/\w+/) {
	    croak("ERROR: Default cmdfile cant be created if cmddir isnt set");
	}
	
	## Create the file and close the fh

	(my $fh, $filename) = tempfile("RiPerlcmd_XXXXXXXX", DIR => $cmddir);
	close($fh);
	$self->add_cmdfile('default', $filename);
    }
    else {
	carp("WARNING: Default cmdfile was created before. Skipping function.");
    }
}

=head2 delete_cmdfile

  Usage: $rih->delete_cmdfile($alias); 

  Desc: Delete a new the command file for the r interfase object, close the
        fh and delete the file.

  Ret: None

  Args: $alias, a scalar

  Side_Effects: Die if no argument is used.

  Example: $rih->delete_cmdfile($alias);

=cut

sub delete_cmdfile {
    my $self = shift;
    my $alias = shift ||
	croak("ERROR: No alias argument was used for delete_cmdfile");

    ## 1) delete from the object

    my $filename = delete($self->{cmdfiles}->{$alias});

    ## 2) delete the file

    remove_tree($filename);    
}

=head2 get_resultfiles

  Usage: my $resultfiles_href = $rih->get_resultfiles(); 

  Desc: Get the result files used by the r interfase object

  Ret: $result_href, a hash reference with key=filename and value=resultfile

  Args: $alias [optional]

  Side_Effects: None

  Example: my %resfiles = %{$rih->get_resultfiles()};
           my $resultfile = $rih->get_resultfiles($alias);

=cut

sub get_resultfiles {
    my $self = shift;
    my $alias = shift;

    if (defined $alias) {
	return $self->{resultfiles}->{$alias};
    }
    else { 
	return $self->{resultfiles};
    }
}


=head2 set_resultfiles

  Usage: $rih->set_resultfiles($resfiles_href); 

  Desc: Set the result files used by the r interfase object

  Ret: None

  Args: $resfile_hashref, an hash reference with key=alias and 
        value=resultfile

  Side_Effects: Die if no argument is used.
                Die if the argument is not a hash reference
                Die if the value is a resultfile that doesnt exists

  Example: $rih->set_cmdfiles($cmdfiles_href); 

=cut

sub set_resultfiles {
    my $self = shift;
    my $resfiles_href = shift ||
	croak("ERROR: No resultfile arg. was used for set_resultfiles()");

    unless(ref($resfiles_href) eq 'HASH') {
	croak("ERROR: resultfiles used for set_resultfiles isnt a hashref.");
    }
    else {
	foreach my $alias (keys %{$resfiles_href}) {

	    my $cfil = $self->get_cmdfiles($alias);
	    unless (defined $cfil) {
		croak("ERROR: alias=$alias doesnt exist associated w. cmdfile");
	    }
	    else {

		unless (-f $cfil) {
		    croak("ERROR: cmdfile=$cfil for alias=$alias doesnt exist");
		}
		
		my $rfil = $resfiles_href->{$alias};
		unless (-f $rfil) {
		    croak("ERROR: resultfile=$rfil for $alias doesnt exist");
		}
	    }
	}
    }
    $self->{resultfiles} = $resfiles_href;
}


=head2 add_resultfile

  Usage: $rih->add_resultfile($alias, $outfile); 

  Desc: Add a new resultfile associated to an alias

  Ret: None

  Args: $alias, a scalar
        $outfile, a scalar with a filepath

  Side_Effects: Die if no argument is used.
                Die if doesnt exists the outfile, or
                the infile associated with this alias

  Example: $rih->add_cmdfile('block1', $filename); 

=cut

sub add_resultfile {
    my $self = shift;
    my $alias = shift ||
	croak("ERROR: No filename arg. was used for add_resultfile function");

    my $filename = $self->get_cmdfiles($alias);

    unless (defined $filename) {
	croak("ERROR: $alias wasnt created or doesnt have cmdfile associated.");
    }
    else {
	unless (-f $filename) {
	    croak("ERROR: cmdfile=$filename for alias=$alias doesnt exist");
	}
    }

    my $outfile = shift ||
	croak("ERROR: No resultfile arg. was used for add_resultfile function");

    unless (-f $outfile) {
	 croak("ERROR: resultfile $outfile doesnt exist for add_resultfile");
    }
    
    $self->{resultfiles}->{$alias} = $outfile;
}


=head2 delete_resultfile

  Usage: $rih->result_cmdfile($alias); 

  Desc: Delete a result file associated with a cmdfile

  Ret: None

  Args: $alias, a scalar

  Side_Effects: Die if no argument is used.

  Example: $rih->delete_resultfile($alias);

=cut

sub delete_resultfile {
    my $self = shift;
    my $alias = shift ||
	croak("ERROR: No alias argument was used for delete_resultfile");

    ## 1) delete from the object

    my $outfile = delete($self->{resultfiles}->{$alias});

    ## 3) delete the file from the system
    remove_tree($outfile);    
}

=head2 get_r_opts_pass

  Usage: my $r_opts_pass = $rih->get_r_opts_pass(); 

  Desc: Get the r_opts_pass variable (options used with the R command)
        when run_command function is used

  Ret: $r_opts_pass, a string

  Args: None

  Side_Effects: None

  Example: my $r_opts_pass = $rih->get_r_opts_pass(); 
           if ($r_opts_pass !~ m/vanilla/) {
              $r_opts_pass .= ' --vanilla';
           }

=cut

sub get_r_opts_pass {
    my $self = shift;
    return $self->{r_opts_pass};
}

=head2 set_r_opts_pass

  Usage: $rih->set_r_opts_pass($r_opts_pass); 

  Desc: Set the r_opts_pass variable (options used with the R command)
        when run_command function is used. Use R -help for more info.
        The most common options used:
        --save                Do save workspace at the end of the session
        --no-save             Don't save it
        --no-environ          Don't read the site and user environment files
        --no-site-file        Don't read the site-wide Rprofile
        --no-init-file        Don't read the user R profile
        --restore             Do restore previously saved objects at startup
        --no-restore-data     Don't restore previously saved objects
        --no-restore-history  Don't restore the R history file
        --no-restore          Don't restore anything
        --vanilla             Combine --no-save, --no-restore, --no-site-file,
                              --no-init-file and --no-environ
        -q, --quiet           Don't print startup message
        --silent              Same as --quiet
        --slave               Make R run as quietly as possible
        --interactive         Force an interactive session
        --verbose             Print more information about progress

        The only opt that can not be set using set_r_opts_pass is --file, 
        it is defined by the commands stored as cmdfiles.

  Ret: None

  Args: $r_opts_pass, a string

  Side_Effects: Remove '--file=' from the r_opts_pass string

  Example: $rih->set_r_opts_pass('--verbose');

=cut

sub set_r_opts_pass {
    my $self = shift;
    my $r_opts_pass = shift;
 
    if ($r_opts_pass =~ m/(--file=.+)\s*/) {  ## If it exists, remove it
	carp("WARNING: --file opt. will be ignore for set_r_opts_pass()");
	$r_opts_pass =~ s/--file=.+\s*/ /g;
    }
    
    $self->{r_opts_pass} = $r_opts_pass;
}

=head2 set_default_r_opts_pass

  Usage: $rih->set_default_r_opts_pass(); 

  Desc: Set the default r_opts_pass for YapRI::Base (R --slave --vanilla)

  Ret: None

  Args: None

  Side_Effects: None

  Example: $rih->set_default_r_opts_pass(); 

=cut

sub set_default_r_opts_pass {
    my $self = shift;

    my $def_r_opts_pass = '--slave --vanilla';

    $self->{r_opts_pass} = $def_r_opts_pass;
}



#################
## CMD OPTIONS ##
#################

=head1 (*) COMMAND METHODS:

=head2 ------------------

=head2 add_command

  Usage: $rih->add_command($r_command, $alias); 

  Desc: Add a R command line to a cmdfile associated with an alias.
        If no filename is used, it will added to the default cmdfile.

  Ret: None

  Args: $r_command, a string with a R command
        $alias, a alias with a cmdfile to add the command

  Side_Effects: Die if the alias used doesnt exist or doesnt have cmdfile
                Add the command to the default if no filename is specified,
                if doesnt exist default cmdfile, it will create it.

  Example: $rih->add_command('x <- c(10, 9, 8, 5)')
           $rih->add_command('x <- c(10, 9, 8, 5)', 'block1')

=cut

sub add_command {
    my $self = shift;
    my $command = shift ||
	croak("ERROR: No command line was added to add_command function");
    my $alias = shift;

    my $filename;
    if (defined $alias) {
	$filename = $self->get_cmdfiles($alias);
	unless (defined $filename) {
	    my $err = "ERROR: alias=$alias doesnt exist or havent cmdfile. ";
	    croak("$err. Aborting add_command().");
	}
    }
    else {
	$filename = $self->get_default_cmdfile();
	unless (defined $filename) {
	    $self->add_default_cmdfile();
	    $filename = $self->get_default_cmdfile();
	}
    }
   
    ## Open as , add and close the file

    open my $fh, '>>', $filename;	
    print $fh "$command\n";
    close($fh);   
}

=head2 get_commands

  Usage: my @commands = $rih->get_commands($alias); 

  Desc: Read the cmdfile associated with an $alias

  Ret: None

  Args: $alias, with a cmdfile associated.

  Side_Effects: Die if $alias doesnt exist or doesnt have cmdfile
                Get commands for default file, by default

  Example: my @commands = $rih->get_commands('block1');
           my @def_commands = $rih->get_commands(); 

=cut

sub get_commands {
    my $self = shift;
    my $alias = shift;

    my @commands = ();

    ## Get the filename from default or the alias
    
    my $filename;
    unless (defined $alias) {
	$filename =  $self->get_default_cmdfile();
    }
    else {
	$filename = $self->get_cmdfiles($alias);
	unless (defined $filename) {
	    croak("ERROR: alias=$alias wasnt created or doesnt have cmdfile.");
	}	
    }

    ## Open and read

    open my $fh, '+<', $filename;
    while(<$fh>) {
	chomp($_);
	push @commands, $_;
    }

    ## It can be used later... close it
    close($fh);

    return @commands;
}

=head2 run_command

  Usage: $rih->run_command($args_href); 

  Desc: Run as command line the R command file

  Ret: None

  Args: $args_href with the following keys/values pair:
        cmdfile => a straing, a cmdfile to execute R comands
        alias   => a string, an alias with a cmdfile associated
        debug   => a scalar, 1 or yes to print R command

  Side_Effects: Die if the wrong args. are used, or if the alias used doesnt
                exist.
                When cmdfile and alias are used at the same time, alias will
                be ignore.
                It will run default cmdfile if no cmdfile or alias is used.

  Example: $rih->run_command($args_href); 

=cut

sub run_command {
    my $self = shift;
    my $args_href = shift;

    my %permargs = (
	alias   => '\w+',
        cmdfile => '\w+',
	debug   => '1|0|yes|no',
	);
    
    my $base_cmd = 'R ';

    ## Add the running opts
    my $r_opts_pass = $self->get_r_opts_pass();

    $base_cmd .= $r_opts_pass;

    ## Check args

    my %args = ();
    if (defined $args_href) {
	unless (ref($args_href) eq 'HASH') {
	    croak("ERROR: Arg. used for run_commands isnt a HASHREF.");
	}
	else {
	    %args = %{$args_href};
	    foreach my $key (keys %args) {
		unless (exists $permargs{$key}) {
		    croak("ERROR: Key=$key isnt permited arg. for run_command");
		}
		else {
		    if ($args{$key} !~ m/$permargs{$key}/i) {
			my $err = "ERROR: Value=$args{$key} isnt a permited ";
			$err .= "value for key=$key at run_command function";
			croak($err);
		    }
		}
	    }	    
	}
    }   
    
    my $err = 'Aborting run_command.';

    ## Check cmddir

    my $cmddir = $self->get_cmddir();
    unless ($cmddir =~ m/\w+/) {
	croak("ERROR: cmddir isnt set. Result files cannot be created. $err");
    }

    ## Get the cmdfile
    ## 1) Through cmdfile

    my $cmdfile = '';
    if (defined $args{cmdfile}) {
	
	$cmdfile = $args{cmdfile};
    }
    else {
	if (defined $args{alias}) {
	
	    $cmdfile = $self->get_cmdfiles($args{alias});
	    unless (defined $cmdfile) {
		my $msg = "ERROR: alias=$args{alias} wasnt created or doesnt";
		croak("$msg have cmdfile. $err");
	    }
	}
	else {
	
	    $cmdfile = $self->get_default_cmdfile();
	    unless (defined $cmdfile && $cmdfile =~ m/\w+/) {
		croak("ERROR: No default cmdfile was found. $err")
	    }
	}
    }

    ## And check it 

    unless (-s $cmdfile) {
	croak("ERROR: cmdfile=$cmdfile doesnt exist. $err");
    }
    
    $base_cmd .= " --file=$cmdfile";

    ## Create a tempfile to store the results
    
    my ($rfh, $resultfile) = tempfile( "RiPerlresult_XXXXXXXX", 
					DIR => $cmddir,
	);
    close($rfh);
	
    $base_cmd .= " > $resultfile";

    ## finally it will run the command

    if (defined $args{debug} && $args{debug} =~ m/1|yes/i) {
	print STDERR "RUNNING COMMAND:\n$base_cmd\n";
    }

    my $run = system($base_cmd);
    
       
    if ($run == 0) {   ## It means success
	if (defined $args{alias}) {
	    $self->add_resultfile($args{alias}, $resultfile);
	}
	else {
	     $self->add_resultfile('default', $resultfile);
	}
    }
    else {
	croak("\nSYSTEM FAILS running R:\nsystem error: $run\n\n");
    }
}


###################
## BLOCK METHODS ##
###################

=head1 (*) BLOCK METHODS:

=head2 ------------------

 They are a collection of methods to wrap add_cmdfile functions and 
 combine different cmdfiles

=head2 combine_blocks

  Usage: $rih->combine_blocks(\@blocks, $new_block); 

  Desc: Create a new block based in an array of defined blocks

  Ret: None

  Args: \@blocks, an array reference with the blocks (cmdfiles aliases) in the
        same order that they will be concatenated.

  Side_Effects: Die if the alias used doesnt exist or doesnt have cmdfile

  Example: $rih->combine_blocks(['block1', 'block3'], 'block43');

=cut

sub combine_blocks {
    my $self = shift;
    my $bl_aref = shift ||
	croak("ERROR: No block aref. was supplied to combine_blocks function");
    my $alias = shift ||
	croak("ERROR: No new name or alias was supplied to combine_blocks()");
    
    unless (ref($bl_aref) eq 'ARRAY') {
	croak("ERROR: $bl_aref used for combine_blocks() isnt an ARRAYREF.");
    }

    ## 1) Get the filenames for all the alias list, read them and 
    ##    put them into an array.

    my @r_cmds = ();
    
    foreach my $bl_alias (@{$bl_aref}) {
	
	my $bl_file = $self->get_cmdfiles($bl_alias);

	## Die if the alias used doesnt exist
	unless (defined $bl_file) {
	    croak("ERROR: alias=$bl_alias at combine_blocks() doesnt exist");
	}
	else {
	    my @commands = $self->get_commands($bl_alias);
	    push @r_cmds, @commands;
	}
    }

    ## 2) Create a temp file for the new block

    $self->add_cmdfile($alias);

    ## 3) Print there the commands

    foreach my $cmdline (@r_cmds) {
	$self->add_command($cmdline, $alias);
    }
}

=head2 create_block

  Usage: $rih->create_block($new_block, $base_block); 

  Desc: Create a new block. A single block can be used as base.

  Ret: None

  Args: $new_block, new name/alias for this block
        $base_block, base block name

  Side_Effects: Die if the base alias used doesnt exist or doesnt have cmdfile

  Example: $rih->create_block('block43', 'block1');

=cut

sub create_block {
    my $self = shift;
    my $alias = shift ||
	croak("ERROR: No new name or alias was supplied to create_block()");
    my $base = shift;

    if (defined $base) {
	$self->combine_blocks([$base], $alias);
    }
    else {
	$self->add_cmdfile($alias);
    }
}

=head2 run_block

  Usage: $rih->run_block($block); 

  Desc: Wrapper of run_command to run a cmdfile as block

  Ret: None

  Args: $block, a block name

  Side_Effects: Die if the base alias used doesnt exist or doesnt have cmdfile

  Example: $rih->run_block('block1');

=cut

sub run_block {
    my $self = shift;
    my $alias = shift ||
	croak("ERROR: No new name or alias was supplied to run_block()");

    $self->run_command({ alias => $alias });
}


#################################
## R. OBJECT/FUNCTIONS METHODS ##
#################################

=head2 r_object_class

  Usage: my $class = $rih->r_object_class($block, $r_object); 

  Desc: Check if exists a r_object in the specified R block. Return 
        undef if the object doesnt exist or the class of the object 

  Ret: $class, a scalar with the class of the r_object

  Args: $block, a scalar, YapRI::Base block
        $r_object, name of the R object 

  Side_Effects: Die if the base alias used doesnt exist or doesnt have cmdfile

  Example: my $class = $rih->r_object_class('BLOCK1', 'mtx');

=cut

sub r_object_class {
    my $self = shift;
    my $block = shift ||
	croak("ERROR: No block name was supplied to r_object_class()");
    my $r_obj = shift ||
	croak("ERROR: No r_object was supplied to r_object_class()");

    ## Check if exist the block (alias) used

    my %cmdfiles = %{$self->get_cmdfiles()};
    unless (defined $cmdfiles{$block}) {
	croak("ERROR: block=$block (alias) doesnt exist for $self object");
    }

    ## Define the class var.

    my $class;

    ## If exist it will create a new block to check the r_object

    my $cblock = 'CHECK_rOBJ_' . $r_obj;
    $self->create_block($cblock, $block);
    
    ## Add the commands and run it
    ## It will run the conditional if(exists("myobject")) before to skip
    ## the error... if doesnt exist, it just will not run class

    $self->add_command('print("init_object_checking_' . $r_obj . '")', $cblock);
    $self->add_command('if(exists("'.$r_obj.'"))class('.$r_obj.')', $cblock);
    $self->add_command('print("end_object_checking_' . $r_obj . '")', $cblock);
    
    $self->run_block($cblock);

    ## Open the result file and parse it

    my $resultfile = $self->get_resultfiles($cblock);
    open my $rfh, '<', $resultfile;

    my $init = 0;
    while (<$rfh>) {
	chomp($_);
	
	## First, disable init as soon as it read it
	if ($_ =~ /end_object_checking_$r_obj/) {
	    $init = 0;
	}
	
        ## Second, catch the data only if init is enable
	if ($init == 1) {
	    if ($_ =~ m/\[1\]\s+"(.+)"/) {
		$class = $1;
	    }
	}

	## Third, enable the init at the end of the line parse
	if ($_ =~ /init_object_checking_$r_obj/) {
	    $init = 1;
	}
	
	
    }
    close($rfh);

    return $class;
}

=head2 r_function_args

  Usage: my %rargs = $rih->r_function_args($r_function); 

  Desc: Get the arguments for a concrete R function.

  Ret: %rargs, a hash with key=r_function_argument, 
                           value=function_default_value

  Args: none

  Side_Effects: Die if no R function argument is used
                Return empty hash if the function doesnt exist
                If the argument doesnt have any value, add <without.value>

  Example: my %plot_args = $rih->r_function_args('plot')

=cut

sub r_function_args {
    my $self = shift;
    my $func = shift ||
	croak("ERROR: No R function argument was used for r_funtion_args()");

    my %fargs = ();

    ## Define blocks

    my $block1 = 'GETARGSR_' . $func . '_1';
    $self->create_block($block1);
    my $block2 = 'GETARGSR_' . $func . '_2';
    $self->create_block($block2);
    my @blocks = ($block1, $block2);

    ## Get environment for function

    my $env;

    my $env_cmd = 'if(exists("'.$func.'"))environment('.$func.')';
    $self->add_command($env_cmd, $block1);
    $self->run_block($block1);
    my $rfile1 = $self->get_resultfiles($block1);
    
    open my $rfh1, '<', $rfile1;
    while(<$rfh1>) {
	if ($_ =~ m/<environment:\snamespace:(.+)>/) {
	    $env = $1;
	}
    }
    close($rfh1);

    ## Now if it has a env (defined $env), it will the second command

    if (defined $env) {

	## Build the command as a conditional to get args for non default
	## objects

	my $arg_cmd = 'if( exists("' . $func . '.default")) ';
	$arg_cmd .= 'args(' . $func . '.default)';
	$arg_cmd .= 'else args(' . $func .')';

	$self->add_command($arg_cmd, $block2);
	$self->run_block($block2);
	my $rfile2 = $self->get_resultfiles($block2);

	open my $rfh2, '<', $rfile2;
	
	## Catch the defaults
	my $fline = '';
	while(<$rfh2>) {
	    chomp($_);
	    $_ =~ s/\s+/ /g;
	    $fline .= $_;
	}
	close($rfh2);
	
	## Parse the line
	$fline =~ s/^function\s*\(\s*//;            ## Remove the head
	$fline =~ s/,\s*?\.{1,3}//;                 ## Remove three dots
	$fline =~ s/\s*\)\s*NULL$//;                ## Remove the tail
	$fline =~ s/\s*=\s*/=/g;                    ## Remove the spaces 
                                                    ## rounding '='

	## keep the array data together, and replace for a tag
	$fline =~ s/c\(.+?\)/<data.vector>/g;
	$fline =~ s/".*?"/<data.scalar.character>/g;
	
	my @fpargs = split(/,/, $fline);
	foreach my $fparg (@fpargs) {
	    $fparg =~ s/^\s+//;
	    if ($fparg =~ m/^(.+)=(.+)$/) {
		my $k = $1;
		$fargs{$k} = $2;
		if ($fargs{$k} =~ m/^\d+$/) {
		    $fargs{$k} = '<data.scalar.numeric>';
		}
		
	    }
	    else {
		$fargs{$fparg} = '<without.value>';
	    }
	}
    }

    ## Finally it will delete the blocks
    
    foreach my $block (@blocks) {
	$self->delete_cmdfile($block);
	$self->delete_resultfile($block);
    }

    return %fargs;
}



#################################
## VARIABLE CONVERSION METHODS ##
#################################



=head2 _rvar_noref

  Usage: my $r_string = _r_var_noref($perl_var); 

  Desc: Internal function to parse a single non-reference perl variable
        (scalar). Equivalence table:
        
        +==================+==============+=============================+
        |  PERL VARIABLE   |  R VARIABLE  | Example                     |
        +==================+==============+===============+=============+
        | undef            | NULL         | $px = undef   | rx <- NULL  |
        +------------------+--------------+---------------+-------------+
        | empty ('' or "") | NA           | $px = ''      | rx <- NA    |
        +------------------+--------------+---------------+-------------+
        | integer          | numeric      | $px = 12      | rx <- 12    |
        +------------------+--------------+---------------+-------------+
        | bigint,bigfloat  | numeric      | $px = '-1.2'  | rx <- -1.2  |
        +------------------+--------------+---------------+-------------+
        | word 'TRUE'      | TRUE         | $px = 'TRUE'  | rx <- TRUE  |
        +------------------+--------------+---------------+-------------+
        | word 'FALSE'     | FALSE        | $px = 'FALSE' | rx <- FALSE |
        +------------------+--------------+---------------+-------------+
        | any other word   | character    | $px = "sun"   | rx <- "sun" |
        +------------------+--------------+---------------+-------------+

  Ret: $r_string, a scalar with the perl2R variable translation

  Args: $perl_var, could be, a scalar or an array reference

  Side_Effects: Die if is used a perl reference.

  Example: my $rvar = _rvar_noref(12);

=cut

sub _rvar_noref {
    my $pvar = shift;

    my $rvar;
    
    if (defined $pvar) {
	if (ref($pvar)) {
	    croak("ERROR: $pvar is a perl reference, unable to convert to R.");
	}
	else {
	    if ($pvar =~ m/./) {
		my $mbf = Math::BigFloat->new($pvar);
		if ($mbf->is_nan()) {
		    if ($pvar =~ m/^(TRUE|FALSE)$/) {
			$rvar = $pvar;
		    }
		    else {
			$rvar = '"' . $pvar .'"';
		    }
		}
		else {
		    $rvar = $mbf->bstr();
		}
	    }
	    else {
		$rvar = 'NA';
	    }
	}
    }
    else {
	$rvar = 'NULL';
    }
    return $rvar;
}

=head2 _rvar_vector

  Usage: my $r_arg = _rvar_vector($arrayref); 

  Desc: Internal function to convert an perl array into a R vector

  Ret: $r_arg, a scalar with the perl2R variable translation

  Args: $arrayref, with the argument list

  Side_Effects: Die if the argument is not an arrayref.

  Example: my $r_vector = _rvar_vector($arrayref);

=cut

sub _rvar_vector {
    my $aref = shift ||
	croak("ERROR: No array ref. was supplied to _rvar_vector");

    my $rvect;
    if (ref($aref) eq 'ARRAY') {
	my @list = ();
	foreach my $el (@{$aref}) {
	    push @list, _rvar_noref($el);
	}
	$rvect = 'c(' . join(', ', @list) . ')';
    }
    else {
	croak("ERROR: $aref supplied to _rvar_vector isnt an array ref.")
    }
    return $rvect;
}



=head2 _rvar_arg

  Usage: my $r_arg = _rvar_arg($hashref); 

  Desc: Internal function to convert an argument in a function in the following
        way:
         2                              ===> '2'
         'YES'                          ===> '"YES"'
         [2, 3]                         ===> 'c(2, 3)'
         { x      => undef }            ===> 'x'
         { type   => "p"   }            ===> 'type = "p"'
         { col    => ["blue", "green"]} ===> 'col = c("blue", "green")'
         { labels => { x => undef } }   ===> 'labels = x'

        Something different from that, will die.

  Ret: $r_arg, a scalar with the perl2R variable translation

  Args: $hashref, with the argument list

  Side_Effects: Die if the argument is not: scalar, array ref or a hash 
                reference.

  Example: my $arg = _rvar_arg({ type => "p" });

=cut

sub _rvar_arg {
    my $parg = shift;

    my $rarg;
    if (defined $parg) {
	if (ref($parg)) {
	    if (ref($parg) eq 'ARRAY') {
		$rarg = _rvar_vector($parg);
	    }
	    elsif (ref($parg) eq 'HASH') {
		my @list = ();
		foreach my $k (sort keys %{$parg}) {
		    if (defined $parg->{$k} && $parg->{$k} =~ m/./) {
			my $sarg = $k . ' = ';
			if (ref($parg->{$k}) eq 'HASH') {
			    $sarg .= join(',', keys %{$parg->{$k}});
			}
			elsif (ref($parg->{$k}) eq 'ARRAY') {
			    $sarg .= _rvar_vector($parg->{$k});
			}
			else {
			    if (ref($parg->{$k})) {
				croak("ERROR: No permited value for R arg.");
			    }
			    $sarg .= _rvar_noref($parg->{$k});
			}
			push @list, $sarg;
		    }
		    else {
			push @list, $k;
		    }
		}
		$rarg = join(', ', @list);
	    }
	}
	else {
	    $rarg = _rvar_noref($parg);
	}
    }
    else {
	$rarg = 'NULL';
    }
    return $rarg
}



=head2 r_var

  Usage: my $r_string = r_var($perl_var); 

  Desc: Parse a perl variable and return a string with the r variable format, 
        For perl-non reference variables, see _rvar_noref

        +==================+=================+==============================+
        |  PERL VARIABLE   |  R VARIABLE     | Example                      |
        +==================+=================+==============+===============+
        | ARRAY REF.       | vector          | $px = [1, 2] | rx <- c(1, 2) |
        +------------------+-----------------+--------------+---------------+
        | HASH REF.        | object/function | see below                    |
        +------------------+-----------------+------------------------------+
        
        $px = { a => undef }, will be just 'a' (R object or function) 
        $px = { mass => '' }, will be just 'mass' (R object or function) 
        $px = { log  => 2  }, will be 'log(2)'
        $px = { log  => [2, { base => 10 }] }, will be 'log(2, base = 10 )'
        $px = { t    => {x => ''} }, will be 't(x)'
        $px = { plot => [{ x => ''}, { main => "TEST"} ]}, will be:
                plot(x, main = "TEST")

        Use array ref. to order the arguments in a function.
        Use hash ref keys to define an argument in an R function      


  Ret: $r_string, a scalar with the perl2R variable translation

  Args: $perl_var, could be, a scalar or an array reference

  Side_Effects: Die if the reference used is not a ARRAY REF or HASH REF.

  Example: my $rvar = r_var([1, 2, 3, "TRUE", "last word"]);

=cut

sub r_var {
    my $pvar = shift;

    my $rvar;

    my $err = "isnt a scalar, ARRAYEF or HASHREF. Unable to convert to R.";
    if (defined $pvar) {
	unless (ref($pvar)) {
	    $rvar = _rvar_noref($pvar);
	}
	else {
	    if (ref($pvar) eq 'ARRAY') {
		$rvar = _rvar_vector($pvar);
	    }
	    elsif (ref($pvar) eq 'HASH') {  ## First level objects or functions
		
		my @list = ();
		foreach my $obj (sort keys %{$pvar}) {
		    my $subvar = $obj;
		    my $args = $pvar->{$obj};        ## Second level, arguments
		
		    if (defined $args && $args =~ m/./) { 
			$subvar .= '(';

			unless (ref($args)) {       ## Just numeric, char...
			    $subvar .= _rvar_noref($args);
			}			
			else {			    			
			    my @arglist = ();

			    if (ref($args) eq 'ARRAY') { ## Ordered by user
			      
				foreach my $arg (@{$args}) {
				    my $targ = _rvar_arg($arg);
				    if (defined $targ && $targ =~ m/./) {
					push @arglist, $targ;
				    }
				}
			    }
			    elsif (ref($args) eq 'HASH') { ## No ordered
				my $targs = _rvar_arg($args);
				if (defined $targs && $targs =~ m/./) {
				    push @arglist, $targs;	
				}
			    }
			    else {
				croak("ERROR: $args $err");
			    }
			    $subvar .= join(', ', @arglist);
			}
			$subvar .= ')'; ## Close list of arguments
		    }
		    push @list, $subvar;
		    
		    ## If there are more than one function or object

		    $rvar = join('; ', @list);
		}
	    }
	    else {
		croak("ERROR: $pvar $err");
	    }
	}
    }
    else {  ## Perl variable undef will be R variable 'NULL'
	$rvar = 'NULL';
    }

    return $rvar;
}




####
1; #
####
