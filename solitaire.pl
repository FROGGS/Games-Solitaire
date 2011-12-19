#!/usr/bin/perl

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

my $WINDOW_WIDTH  = 800;
my $WINDOW_HEIGHT = 600;

my $display      = SDL::Video::set_video_mode(
    $WINDOW_WIDTH, $WINDOW_HEIGHT, 32, SDL_HWSURFACE | SDL_HWACCEL
); # SDL_DOUBLEBUF

my $layers       = SDLx::LayerManager->new();
my $event        = SDL::Event->new();
my $loop         = 1;
my $last_click   = Time::HiRes::time;
my $fps          = SDLx::FPS->new(fps => 60);
my @selected_cards = ();
my $left_mouse_down = 0;
my @rewind_deck_1_position = (  20,  20);
my @rewind_deck_1_hotspot  = (  40,  40);
my @rewind_deck_2_position = ( 130,  20);
my @rewind_deck_2_hotspot  = ( 150,  40);
my @left_stack_position    = (  20, 200);
my @left_stack_hotspot     = (  40, 220);
my @left_target_position   = ( 350,  20);
my @left_target_hotspot    = ( 370,  40);
my @space_between_stacks   = ( 110,  20);
my $hotspot_offset         = 20;
my %KING_CARDS             = (map { $_ => 1 } (12,25,38,51));

init_background();
init_cards();
my @rects = @{$layers->blit($display)};
SDL::Video::update_rects($display, @rects) if scalar @rects;
game();

sub _x
{
    return shift->pos->x;
}

sub _y
{
    return shift->pos->y;
}

sub _is_num {
    return shift =~ m{\A\d+\z};
}

sub _handle_mouse_button_up
{
    my ($handler) = @_;

    $left_mouse_down = 0 if $event->button_button == SDL_BUTTON_LEFT;
    $handler->{on_drop}->();

    my $dropped = 1;
    while($dropped) {
        $dropped = 0;
        for(-1..6) {
            my $layer = $_ == -1
                      ? $layers->by_position( @rewind_deck_2_hotspot )
                      : $layers->by_position( $left_stack_hotspot[0] + $space_between_stacks[0] * $_, $left_stack_hotspot[1] );
            my @stack = ($layer, @{$layer->ahead});
               $layer = pop @stack if scalar @stack;

            if(defined $layer
            && $layer->data->{id} =~ m/\d+/
            && $layer->data->{visible}
            && !scalar @{$layer->ahead}) {
                my $target = $layers->by_position(
                    $left_target_hotspot[0] + $space_between_stacks[0] * int($layer->data->{id} / 13), $left_target_hotspot[1]
                );

                if(can_drop($layer->data->{id}, $target->data->{id})) {

                    $layer->attach($event->button_x, $event->button_y);
                    $layer->foreground;

                    my $square = sub { my $n = shift; return $n*$n; };

                    my $calc_dx = sub {
                        return ( _x($target) - _x($layer) );
                    };
                    my $calc_dy = sub {
                        return ( _y($target) - _y($layer) );
                    };

                    my $calc_dist = sub {
                        return sqrt(
                            $square->($calc_dx->()) + $square->($calc_dy->())
                        );
                    };

                    my $dist  = 999;
                    my $steps = $calc_dist->() / 40;

                    my $step_x = $calc_dx->() / $steps;
                    my $step_y = $calc_dy->() / $steps;

                    while($dist > 40) {

                        #$w += $layer->clip->w - $x;
                        #$h += $layer->clip->h - $y;
                        $layer->pos(
                            _x($layer) + $step_x, _y($layer) + $step_y
                        );
                        $layers->blit($display);
                        #SDL::Video::update_rect($display, $x, $y, $w, $h);
                        SDL::Video::update_rect($display, 0, 0, 0, 0);
                        $fps->delay;

                        $dist = $calc_dist->();
                    }
                    $layer->detach_xy(_x($target), _y($target));
                    show_card(pop @stack) if scalar @stack;
                    $dropped = 1;
                }
            }
        }
    }
}

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
            _handle_mouse_button_up($handler);
        }
        elsif ($type == SDL_KEYDOWN) {
            if($event->key_sym == SDLK_PRINT) {

                my $screen_shot_index = 1;

                # TODO : perhaps do it using max.
                foreach my $bmp_fn (<Shot*\.bmp>)
                {
                    if (my ($new_index) = $bmp_fn =~ /Shot(\d+)\.bmp/)
                    {
                        if ($new_index >= $screen_shot_index)
                        {
                            $screen_shot_index = $new_index + 1;
                        }
                    }
                }

                SDL::Video::save_BMP($display, sprintf("Shot%04d.bmp", $screen_shot_index ));
            }
            elsif($event->key_sym == SDLK_ESCAPE) {
                $handler->{on_quit}->();
            }
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
                    # to empty field
                    if($stack[0]->data->{id} =~ m/empty_stack/
                       && can_drop($selected_cards[0]->data->{id}, $stack[0]->data->{id})) {
                        @position_before = @{$layers->detach_xy($stack[0]->pos->x, $stack[0]->pos->y)};
                        $dropped         = 1;
                    }

                    # to face-up card
                    elsif($stack[0]->data->{visible}
                       && can_drop($selected_cards[0]->data->{id}, $stack[0]->data->{id})) {
                        @position_before = @{$layers->detach_xy($stack[0]->pos->x, $stack[0]->pos->y + $space_between_stacks[1])};
                        $dropped         = 1;
                    }

                    if($dropped && scalar @position_before) {
                        $position_before[0] += $hotspot_offset; # transparent border
                        $position_before[1] += $hotspot_offset;
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
                            $layer->detach_xy(@rewind_deck_2_position);
                            show_card($layer);
                        }
                    }
                    elsif($layer->data->{id} =~ m/rewind_deck/) {
                        $layer = $layers->by_position(@rewind_deck_2_hotspot);
                        my @cards = ($layer, @{$layer->behind});
                        pop @cards;
                        pop @cards;
                        foreach(@cards) {
                            $_->attach(@rewind_deck_2_hotspot);
                            $_->foreground;
                            $_->detach_xy(@rewind_deck_1_position);
                            hide_card(@rewind_deck_1_hotspot);
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
                my $target = $layers->by_position(
                    $left_target_hotspot[0] + 11 * int($layer->data->{id} / 13), $left_target_hotspot[1]
                );

                if(can_drop($layer->data->{id}, $target->data->{id})) {
                    $layer->attach($event->button_x, $event->button_y);
                    $layer->foreground;
                    $layer->detach_xy(_x($target), _y($target));
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
    my $stack      = $layers->by_position($left_target_hotspot[0] + $space_between_stacks[0] * $card_color, $left_target_hotspot[1]);

    #my @stack = $layers->get_layers_behind_layer($stack);
    #my @stack = $layers->get_layers_ahead_layer($stack);

    # Kings can be put on empty fields.
    if (exists($KING_CARDS{$card})) {
        return 1 if $target =~ m/empty_stack/;
    }

    # Aces can be put on empty field (at upper right)
    if('0,13,26,39' =~ m/\b\Q$card\E\b/ && $target =~ m/empty_target_\Q$card_color\E/) {
        return 1;
    }

    my $are_nums = _is_num($card) && _is_num($target);

    if ($are_nums
        && $card == $target + 1
        && $target == $stack->data->{id}
        && $stack->data->{visible}
    )
    {
        return 1;
    }

    if($are_nums
        && '12,25,38,51' !~ m/\b\Q$card\E\b/
        && ($card + 14 == $target || $card + 40 == $target
         || $card - 12 == $target || $card - 38 == $target)
    )
    {
        return 1;
    }

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
    $layers->add(SDLx::Layer->new(SDL::Image::load('data/background.png'),                           {id => 'background'}));
    $layers->add(SDLx::Layer->new(SDL::Image::load('data/empty_stack.png'), @rewind_deck_1_position, {id => 'rewind_deck'}));
    $layers->add(SDLx::Layer->new(SDL::Image::load('data/empty_stack.png'), @rewind_deck_2_position, {id => 'empty_deck'}));

    $layers->add(
        SDLx::Layer->new(SDL::Image::load('data/empty_target_' . $_ . '.png'),
        $left_target_position[0] + $space_between_stacks[0] * $_, $left_target_position[1],
        {id => 'empty_target_' . $_})) for(0..3);

    $layers->add(
        SDLx::Layer->new(SDL::Image::load('data/empty_stack.png'),
        $left_stack_position[0]  + $space_between_stacks[0] * $_, $left_stack_position[1],
        {id => 'empty_stack'}))        for(0..6);
}

sub init_cards {
    my $stack_index    = 0;
    my $stack_position = 0;
    my @card_value     = fisher_yates_shuffle([0..51]);
    for(0..51)
    {
        my $image   = 'data/card_back.png';
        my $visible = 0;
        my ($x, $y) = @rewind_deck_1_position;

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
            $x = $left_stack_position[0] + $space_between_stacks[0] * $stack_index;
            $y = $left_stack_position[1] + $space_between_stacks[1] * $stack_position;
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
