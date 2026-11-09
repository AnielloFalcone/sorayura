use strict;
use warnings;
use DynaLoader ();

my ($library, $action) = @ARGV;
die "Invalid Now Playing request\n" unless @ARGV == 2
  && $action =~ /\A(?:read|artwork|play|pause|next track|previous track)\z/;
$ENV{SORAYURA_MEDIA_ACTION} = $action;
my $handle = DynaLoader::dl_load_file($library, 0) or die "Cannot load Now Playing helper\n";
my $symbol = DynaLoader::dl_find_symbol($handle, 'sorayura_now_playing') or die "Missing Now Playing entry point\n";
DynaLoader::dl_install_xsub('main::now_playing', $symbol);
now_playing();
