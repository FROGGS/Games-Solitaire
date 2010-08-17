#!/usr/bin/perl

=pod TODO

( ) Karten ablegen automatisch
( ) LayerManager: indirekte überdeckende Karten
( ) Karten oben rechts nicht oben rechts anlegbar
( ) Doppelklick legt auf falsche Farbe (kreuz 10 auf roten bube)
( ) Könige können oben rechts nicht abgelegt werden

=cut

package Games::Solitaire;

use strict;
use warnings;
use Time::HiRes;

use SDL;
use SDL::Event;
use SDL::Events;
use SDL::Rect;
use SDL::Surface;
use SDL::Video;

use SDLx::SFont;
use SDLx::Surface;
use SDLx::Sprite;

use SDLx::LayerManager;
use SDLx::Layer;
use SDLx::FPS;

SDL::init(SDL_INIT_VIDEO);
my $display      = SDL::Video::set_video_mode(800, 600, 32, SDL_HWSURFACE | SDL_HWACCEL); # SDL_DOUBLEBUF
my $layers       = SDLx::LayerManager->new();
my $event        = SDL::Event->new();
my $loop         = 1;
my $last_click   = Time::HiRes::time;
my $fps          = SDLx::FPS->new(fps => 60);
my @selected_cards = ();
my $left_mouse_down = 0;

init_background();
init_cards();
my @rects = @{$layers->blit($display)};
SDL::Video::update_rects($display, @rects) if scalar @rects;
game();

sub event_loop
{
    my $handler = shift;
    
    SDL::Events::pump_events();
    while(SDL::Events::poll_event($event))
    {
        my $type = $event->type;

        if ($type == SDL_MOUSEBUTTONDOWN) {
            $left_mouse_down = 1 if $event->button_button == SDL_BUTTON_LEFT;
            my $time = Time::HiRes::time;
            if ($time - $last_click >= 0.3) {
                $handler->{on_click}->();
            }
            else {
                $handler->{on_dblclick}->();
            }
            $last_click = $time;
        }
        elsif ($type == SDL_MOUSEMOTION) {
            if ($left_mouse_down) {
                $handler->{on_drag}->();
            }
            else {
                $handler->{on_mousemove}->();
            }
        }
        elsif ($type == SDL_MOUSEBUTTONUP) {
            $left_mouse_down = 0 if $event->button_button == SDL_BUTTON_LEFT;
            $handler->{on_drop}->();

            my $dropped = 1;
            while($dropped) {
                $dropped = 0;
                for(-1..6) {
                    my $layer = $_ == -1
                              ? $layers->by_position( 150, 40 )
                              : $layers->by_position( 40 + 110 * $_, 220 );
                    my @stack = ($layer, @{$layer->ahead});
                       $layer = pop @stack if scalar @stack;
                    
                    if(defined $layer
                    && $layer->data->{id} =~ m/\d+/
                    && $layer->data->{visible}
                    && !scalar @{$layer->ahead}) {
                        my $target = $layers->by_position(370 + 110 * int($layer->data->{id} / 13), 40);

                        if(can_drop($layer->data->{id}, $target->data->{id})) {
                            $layer->attach($event->button_x, $event->button_y);
                            $layer->foreground;
                            $layer->detach_xy($target->pos->x, $target->pos->y);
                            show_card(pop @stack) if scalar @stack;
                            $dropped = 1;
                        }
                    }
                }
            }
        }
        elsif ($type == SDL_KEYDOWN) {
            $handler->{on_quit}->() if $event->key_sym == SDLK_ESCAPE;
            $handler->{on_keydown}->();
        }
        elsif ($type == SDL_QUIT) {
            $handler->{on_quit}->();
        }
    }
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
            # @selected_cards contains whatever set
            # of cards the player is moving around
            if(scalar @selected_cards) {
                my @selected_cards_ = ();
                push(@selected_cards_, $_->foreground) for @selected_cards;
                
                my @stack           = scalar @selected_cards_
                                    ? @{$selected_cards[0]->behind}
                                    : ();
                my $dropped         = 0;
                my @position_before = ();
                
                if(scalar @stack) {
                    # auf leeres Feld
                    if($stack[0]->data->{id} =~ m/empty_stack/
                       && can_drop($selected_cards[0]->data->{id}, $stack[0]->data->{id})) {
                        @position_before = @{$layers->detach_xy($stack[0]->pos->x, $stack[0]->pos->y)};
                        $dropped         = 1;
                    }
                    
                    # auf offene Karte
                    elsif($stack[0]->data->{visible}
                       && can_drop($selected_cards[0]->data->{id}, $stack[0]->data->{id})) {
                        @position_before = @{$layers->detach_xy($stack[0]->pos->x, $stack[0]->pos->y + 20)};
                        $dropped         = 1;
                    }
                    
                    if($dropped && scalar @position_before) {
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
                my $layer = $layers->by_position($event->button_x, $event->button_y);
                
                if(defined $layer) {
                    if($layer->data->{id} =~ m/^\d+$/) {
                        if($layer->data->{visible}) {
                            @selected_cards = ($layer, @{$layer->ahead});
                            $layers->attach(@selected_cards, $event->button_x, $event->button_y);
                        }
                        elsif(!scalar @{$layer->ahead}) {
                            $layer->attach($event->button_x, $event->button_y);
                            $layer->foreground;
                            $layer->detach_xy(130, 20);
                            show_card($layer);
                        }
                    }
                    elsif($layer->data->{id} =~ m/rewind_deck/) {
                        $layer = $layers->by_position(150, 40);
                        my @cards = ($layer, @{$layer->behind});
                        pop @cards;
                        pop @cards;
                        foreach(@cards) {
                            $_->attach(150, 40);
                            $_->foreground;
                            $_->detach_xy(20, 20);
                            hide_card(40, 40);
                        }
                    }
                }
            }
        },
        on_dblclick => sub {
            $last_click = 0;
            $layers->detach_back;

            my $layer  = $layers->by_position($event->button_x, $event->button_y);

            if(defined $layer
            && !scalar @{$layer->ahead}
            && $layer->data->{id} =~ m/\d+/
            && $layer->data->{visible}) {
                my $target = $layers->by_position(370 + 110 * int($layer->data->{id} / 13), 40);

                if(can_drop($layer->data->{id}, $target->data->{id})) {
                    $layer->attach($event->button_x, $event->button_y);
                    $layer->foreground;
                    $layer->detach_xy($target->pos->x, $target->pos->y);
                    show_card($event->button_x, $event->button_y);
                }
            }
        },
        on_mousemove => sub {
        },
        on_keydown => sub {
        },
    };
    
    while($loop) {
        event_loop($handler);
        @rects = @{$layers->blit($display)};
        SDL::Video::update_rect($display, 0, 0, 0, 0);# if scalar @rects;
        $fps->delay;
    }
}

sub can_drop {
    my $card       = shift;
    my $card_color = int($card / 13);
    my $target     = shift;
    my $stack      = $layers->by_position(370 + 110 * $card_color, 40);
    
    #my @stack = $layers->get_layers_behind_layer($stack);
    #my @stack = $layers->get_layers_ahead_layer($stack);

    # Könige dürfen auf leeres Feld
    if('12,25,38,51' =~ m/\b\Q$card\E\b/) {
        return 1 if $target =~ m/empty_stack/;
    }
    
    # Asse dürfen auf leeres Feld rechts oben
    if('0,13,26,39' =~ m/\b\Q$card\E\b/ && $target =~ m/empty_target_\Q$card_color\E/) {
        return 1;
    }
    
    if($card =~ m/^\d+$/ && $target =~ m/^\d+$/
    && $card == $target + 1
    && $target == $stack->data->{id}
    && $stack->data->{visible}) {
        return 1;
    }
    
    return 1 if($card =~ m/^\d+$/ && $target =~ m/^\d+$/
             && '12,25,38,51' !~ m/\b\Q$card\E\b/
             && ($card + 14 == $target || $card + 40 == $target
              || $card - 12 == $target || $card - 38 == $target)
             );
    
    return 0;
}

sub hide_card {
    my $layer = (scalar @_ == 2) ? $layers->by_position(@_) : shift;

    if($layer
    && $layer->data->{id} =~ m/\d+/
    && $layer->data->{visible}) {
        $layer->surface(SDL::Image::load('data/card_back.png'));
        $layer->data({id => $layer->data->{id}, visible => 0});
    }
}

sub show_card {
    my $layer = (scalar @_ == 2) ? $layers->by_position(@_) : shift;

    if($layer
    && $layer->data->{id} =~ m/\d+/
    && !$layer->data->{visible}) {
        $layer->surface(SDL::Image::load('data/card_' . $layer->data->{id} . '.png'));
        $layer->data({id => $layer->data->{id}, visible => 1});
    }
}

my @layers_;
sub init_background {
    $layers->add(SDLx::Layer->new(SDL::Image::load('data/background.png'),                                   {id => 'background'}));
    $layers->add(SDLx::Layer->new(SDL::Image::load('data/empty_stack.png'),              20,  20,            {id => 'rewind_deck'}));
    $layers->add(SDLx::Layer->new(SDL::Image::load('data/empty_stack.png'),             130,  20,            {id => 'empty_deck'}));
    $layers->add(SDLx::Layer->new(SDL::Image::load('data/empty_target_' . $_ . '.png'), 350 + 110 * $_,  20, {id => 'empty_target_' . $_})) for(0..3);
    $layers->add(SDLx::Layer->new(SDL::Image::load('data/empty_stack.png'),              20 + 110 * $_, 200, {id => 'empty_stack'}))        for(0..6);
}

sub init_cards {
    my $stack_index    = 0;
    my $stack_position = 0;
    my @card_value     = fisher_yates_shuffle([0..51]);
    for(0..51)
    {
        my $image   = 'data/card_back.png';
        my $visible = 0;
        my $x       = 20;
        my $y       = 20;
        
        if($_ < 28)
        {
            if($stack_position > $stack_index)
            {
                $stack_index++;
                $stack_position = 0;
            }
            if($stack_position == $stack_index)
            {
                $image   = 'data/card_' . $card_value[$_] . '.png';
                $visible = 1;
            }
            $x =  20 + 110 * $stack_index;
            $y = 200 +  20 * $stack_position;
            $stack_position++;
        }
        
        $layers->add(SDLx::Layer->new(SDL::Image::load($image), $x, $y, {id => $card_value[$_], visible => $visible}));
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
