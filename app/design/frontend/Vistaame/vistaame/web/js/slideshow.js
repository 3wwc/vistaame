/**
 * Vistaame Slideshow and Product Carousel JavaScript
 */

define([
    'jquery',
    'domReady!'
], function ($) {
    'use strict';

    // Initialize slideshow
    function initSlideshow() {
        const $slideshow = $('#heroSlideshow');
        const $slides = $slideshow.find('.slide');
        const $indicators = $slideshow.find('.indicator');
        let currentSlide = 0;
        let slideInterval;

        function showSlide(index) {
            $slides.removeClass('active');
            $indicators.removeClass('active');
            
            $slides.eq(index).addClass('active');
            $indicators.eq(index).addClass('active');
        }

        function nextSlide() {
            currentSlide = (currentSlide + 1) % $slides.length;
            showSlide(currentSlide);
        }

        function startSlideshow() {
            slideInterval = setInterval(nextSlide, 5000);
        }

        function stopSlideshow() {
            clearInterval(slideInterval);
        }

        // Manual navigation
        $indicators.on('click', function() {
            const slideIndex = $(this).data('slide');
            currentSlide = slideIndex;
            showSlide(currentSlide);
            stopSlideshow();
            startSlideshow(); // Restart timer
        });

        // Pause on hover
        $slideshow.on('mouseenter', stopSlideshow);
        $slideshow.on('mouseleave', startSlideshow);

        // Start slideshow
        startSlideshow();
    }

    // Initialize product carousels
    function initProductCarousels() {
        $('.product-carousel').each(function() {
            const $carousel = $(this);
            const $items = $carousel.find('.product-item');
            
            // Add hover effects
            $items.on('mouseenter', function() {
                $(this).addClass('hover');
            }).on('mouseleave', function() {
                $(this).removeClass('hover');
            });

            // Add to cart functionality
            $items.find('.add-to-cart').on('click', function(e) {
                e.preventDefault();
                const $button = $(this);
                const $item = $button.closest('.product-item');
                const productName = $item.find('.product-name').text();
                
                // Add loading state
                $button.text('Adicionando...').prop('disabled', true);
                
                // Simulate add to cart (replace with actual Magento functionality)
                setTimeout(function() {
                    $button.text('Adicionado!').removeClass('add-to-cart').addClass('added');
                    
                    // Show success message
                    showNotification('Produto adicionado ao carrinho: ' + productName);
                    
                    // Reset button after 2 seconds
                    setTimeout(function() {
                        $button.text('Adicionar ao Carrinho').prop('disabled', false).removeClass('added').addClass('add-to-cart');
                    }, 2000);
                }, 1000);
            });
        });
    }

    // Show notification
    function showNotification(message) {
        const $notification = $('<div class="vistaame-notification">' + message + '</div>');
        $('body').append($notification);
        
        setTimeout(function() {
            $notification.addClass('show');
        }, 100);
        
        setTimeout(function() {
            $notification.removeClass('show');
            setTimeout(function() {
                $notification.remove();
            }, 300);
        }, 3000);
    }

    // Initialize everything when DOM is ready
    $(document).ready(function() {
        initSlideshow();
        initProductCarousels();
    });

    return {
        initSlideshow: initSlideshow,
        initProductCarousels: initProductCarousels
    };
});
