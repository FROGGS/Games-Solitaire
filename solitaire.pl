#!/usr/bin/perl

=pod TODO

( ) Karten ablegen automatisch
( ) Platzhalter neben Stapel
( ) LayerManager: indirekte überdeckende Karten

=cut



package Games::Solitaire;

use strict;
use warnings;
use Time::HiRes;

use SDL;
#use SDL::Color;
use SDL::Event;
use SDL::Events;
#use SDL::GFX::Primitives;
#use SDL::GFX::Rotozoom;
#use SDL::Image;
use SDL::Rect;
use SDL::Surface;
#use SDL::TTF;
#use SDL::TTF::Font;
use SDL::Video;

#use SDLx::FPS;
use SDLx::SFont;
use SDLx::Surface;
use SDLx::Sprite;

use lib 'lib';
use SDLx::LayerManager;

SDL::init(SDL_INIT_VIDEO);
my $display      = SDL::Video::set_video_mode(800, 600, 32, SDL_HWSURFACE | SDL_DOUBLEBUF | SDL_HWACCEL);
my $layers       = SDLx::LayerManager->new();
my $event        = SDL::Event->new();
my $loop         = 1;
my $usec         = Time::HiRes::time;
my $last_click   = Time::HiRes::time;
#my @rects        = ();
#my $fps          = SDLx::FPS->new(fps => 30);
my @selected_cards = ();
my $left_mouse_down = 0;

#SDL::TTF::init();
#my $sfont = SDLx::SFont->new('data/font.png');

#my $font      = SDL::TTF::Font->new('data/gnuolane free.ttf', 20);
#my $font_rect = SDL::Rect->new(10, 10, 70, 30);

init_background();
init_cards();
$layers->blit($display);
game();

sub draw {
    my $usec_ = Time::HiRes::time;
    if($usec_ > $usec + 5/60) {
        $layers->blit($display);
        SDL::Video::flip($display);
        $usec = $usec_;
    }
}

sub event_loop
{
    my $handler = shift;
    
    SDL::Events::pump_events();
    while(SDL::Events::poll_event($event))
    {
        $left_mouse_down = 1            if $event->type == SDL_MOUSEBUTTONDOWN && $event->button_button == SDL_BUTTON_LEFT;
        $left_mouse_down = 0            if $event->type == SDL_MOUSEBUTTONUP   && $event->button_button == SDL_BUTTON_LEFT;
    
        $handler->{on_quit}->()         if defined $handler->{on_quit}      && ($event->type == SDL_QUIT || ($event->type == SDL_KEYDOWN && $event->key_sym == SDLK_ESCAPE));
        $handler->{on_keydown}->()      if defined $handler->{on_keydown}   && $event->type == SDL_KEYDOWN;
        $handler->{on_mousemove}->()    if defined $handler->{on_mousemove} && $event->type == SDL_MOUSEMOTION && !$left_mouse_down;
        $handler->{on_drag}->()         if defined $handler->{on_drag}      && $event->type == SDL_MOUSEMOTION && $left_mouse_down;
        $handler->{on_drop}->()         if defined $handler->{on_drop}      && $event->type == SDL_MOUSEBUTTONUP;
        $handler->{on_click}->()        if defined $handler->{on_click}     && $event->type == SDL_MOUSEBUTTONDOWN && Time::HiRes::time - $last_click >= 0.3;
        $handler->{on_dblclick}->()     if defined $handler->{on_dblclick}  && $event->type == SDL_MOUSEBUTTONDOWN && Time::HiRes::time - $last_click < 0.3;
        
        $last_click = Time::HiRes::time if $event->type == SDL_MOUSEBUTTONDOWN;
        draw();
    }
}

sub menu
{
    my $handler =
    {
        on_quit    => sub {
            $loop = 0;
        },
    };
    
    event_loop($handler);
}

sub game
{
    my @selected_cards = ();
    my $x = 0;
    my $y = 0;
    my $handler =
    {
        on_quit    => sub {
            $loop = 0;
        },
        on_drag => sub {
        },
        on_drop    => sub {
            if(scalar @selected_cards) {
                @selected_cards = $layers->foreground(@selected_cards);
                
                my @stack = $layers->get_layers_behind_layer($selected_cards[0]);

                my $dropped = 0;
                my @position_before = ();
                
                if(scalar @stack) {
                    # auf leeres Feld
                    if($layers->[$stack[0]]->{options}->{id} =~ m/empty_stack/
                       && can_drop($layers->[$selected_cards[0]]->{options}->{id}, $layers->[$stack[0]]->{options}->{id})) {
                        @position_before = $layers->detach_xy($layers->[$stack[0]]->{layer}->x, $layers->[$stack[0]]->{layer}->y);
                        $dropped         = 1;
                    }
                    
                    # auf offene Karte
                    elsif($layers->[$stack[0]]->{options}->{visible}
                       && can_drop($layers->[$selected_cards[0]]->{options}->{id}, $layers->[$stack[0]]->{options}->{id})) {
                        @position_before = $layers->detach_xy($layers->[$stack[0]]->{layer}->x, $layers->[$stack[0]]->{layer}->y + 20);
                        $dropped         = 1;
                    }
                    
                    if($dropped) {
                        $position_before[0] += 20; # transparenter Rand
                        $position_before[1] += 20;
                        show_card(@position_before);
                    }
                }
                
                $layers->detach_back unless $dropped;
            }
            @selected_cards = ();
        },
        on_click => sub {
            unless(scalar @selected_cards) {
                my $layer = $layers->get_layer_by_position($event->button_x, $event->button_y);
                
                if($layer > 0 && $layers->[$layer]->{options}->{id} =~ m/\d+/
                              && $layers->[$layer]->{options}->{visible}) {
                    @selected_cards = ($layer, $layers->get_layers_ahead_layer($layer));
                    $layers->attach(@selected_cards, $event->button_x, $event->button_y);
                }
            }
        },
        on_dblclick => sub {
            $last_click = 0;
            $layers->detach_back;
            my $layer  = $layers->get_layer_by_position($event->button_x, $event->button_y);
            if($layer > 0 && $layers->[$layer]->{options}->{id} =~ m/\d+/
                          && $layers->[$layer]->{options}->{visible}) {
                my $target = $layers->get_layer_by_position(370 + 110 * int($layers->[$layer]->{options}->{id} / 13), 40);

                if(can_drop($layers->[$layer]->{options}->{id}, $layers->[$target]->{options}->{id})) {
                    $layers->attach($layer, $event->button_x, $event->button_y);
                    $layers->foreground($layer);
                    $layers->detach_xy($layers->[$target]->{layer}->x, $layers->[$target]->{layer}->y);
                    show_card($event->button_x, $event->button_y);
                }
            }
        },
    };
    
    while($loop) {
        event_loop($handler);
        draw();
        #$fps->delay;
    }
}

sub can_drop {
    my $card   = shift;
    my $card_color = int($card / 13);
    my $target = shift;
    my $stack = $layers->get_layer_by_position(370 + 110 * $card_color, 40);
    
    printf("%s => %s\n", $card, $target);
    #my @stack = $layers->get_layers_behind_layer($stack);
    #my @stack = $layers->get_layers_ahead_layer($stack);

    # Könige dürfen auf leeres Feld
    if('12,25,38,51' =~ m/\b\Q$card\E\b/) {
        return $target =~ m/empty_stack/ ? 1 : 0;
    }
    
    # Asse dürfen auf leeres Feld rechts oben
    if('0,13,26,39' =~ m/\b\Q$card\E\b/ && $target =~ m/empty_target_\Q$card_color\E/) {
        return 1;
    }
    
    printf("%s == %s\n", $target, $layers->[$stack]->{options}->{id});
    if($card =~ m/^\d+$/ && $target =~ m/^\d+$/
    && $card == $target + 1
    && $target == $layers->[$stack]->{options}->{id}) {
        return 1;
    }
    
    printf("%s => %s\n", $card, $target);
    
    return 1 if($card =~ m/^\d+$/ && $target =~ m/^\d+$/
             && ($card + 14 == $target || $card + 40 == $target
              || $card - 12 == $target || $card - 38 == $target)
             );
    
    return 0;
}

sub show_card {
    my @position = @_;
    my $layer = $layers->get_layer_by_position(@position);

    if($layer > 0 && $layers->[$layer]->{options}->{id} =~ m/\d+/
    && -e 'data/card_' . $layers->[$layer]->{options}->{id} . '.png') {
        $layers->set(
            $layer,
            SDLx::Sprite->new(
                image => 'data/card_' . $layers->[$layer]->{options}->{id} . '.png',
                x => $layers->[$layer]->{layer}->x,
                y => $layers->[$layer]->{layer}->y),
            {id => $layers->[$layer]->{options}->{id}, visible => 1}
        );
    }
}

sub init_background {
    my $background   = SDLx::Sprite->new(image => 'res/0002.png');
       $layers->add($background, {id => 'background'});
    for(0..6) {
        my $empty_stack  = SDLx::Sprite->new(image => 'data/empty_stack.png');
        $empty_stack->y( 200 );
        $empty_stack->x( 20 + 110 * $_ );
        $layers->add($empty_stack, {id => 'empty_stack'});
    }
    
    for(0..3) {
        my $empty_stack  = SDLx::Sprite->new(image => 'data/empty_target_' . $_ . '.png');
        $empty_stack->y( 20 );
        $empty_stack->x( 350 + 110 * $_ );
        $layers->add($empty_stack, {id => 'empty_target_' . $_});
    }
}

sub init_cards {
    my $stack_index    = 0;
    my $stack_position = 0;
    my @card_value     = fisher_yates_shuffle([0..51]);
    for(0..51)
    {
        my $card    = SDLx::Sprite->new(image => 'data/card_back.png');
        my $visible = 0;
        
        if($_ < 28)
        {
            if($stack_position > $stack_index)
            {
                $stack_index++;
                $stack_position = 0;
            }
            if($stack_position == $stack_index)
            {
                $card    = SDLx::Sprite->new(image => 'data/card_' . $card_value[$_] . '.png');
                $visible = 1;
            }
            $card->x(  20 + 110 * $stack_index );
            $card->y( 200 +  20 * $stack_position);
            $stack_position++;
        }
        else
        {
            $stack_index = 7;
            $card->x( 20 );
            $card->y( 20 );
        }
        $layers->add($card, {id => $card_value[$_], visible => $visible});
    }
}

sub fisher_yates_shuffle
{
    my $array = shift;
    my $i;
    for ($i = @$array; --$i; ) {
        my $j = int rand ($i+1);
        next if $i == $j;
        @$array[$i,$j] = @$array[$j,$i];
    }
    return @$array;
}
