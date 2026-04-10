document.addEventListener('DOMContentLoaded', async () => {
    const placeholder = document.getElementById('nav-placeholder');
    if (!placeholder) {
        return;
    }

    try {
        const response = await fetch('nav.html', { cache: 'no-store' });
        if (!response.ok) {
            throw new Error(`Failed to load nav.html: ${response.status}`);
        }

        placeholder.innerHTML = await response.text();
        initializeNavigation();
    } catch (error) {
        console.error('Navigation load error:', error);
    }
});

function initializeNavigation() {
    const currentPage = document.body.dataset.navCurrent;
    const navItems = document.querySelectorAll('[data-nav-key]');

    navItems.forEach((item) => {
        if (item.dataset.navKey === currentPage) {
            item.classList.add('nav-active');
        }
    });

    const memberLink = document.querySelector('[data-member-link]');
    if (memberLink) {
        memberLink.addEventListener('click', () => {
            memberLink.href = 'index.html?memberLogin=1';
        });
    }

    const menuButton = document.getElementById('menu-btn');
    const mainNavLinks = document.getElementById('main-nav-links');
    if (menuButton && mainNavLinks) {
        const isDesktop = () => window.matchMedia('(min-width: 1024px)').matches;

        const closeMobileMenu = () => {
            mainNavLinks.classList.remove('is-open');
            menuButton.setAttribute('aria-expanded', 'false');
        };

        const syncMenuState = () => {
            if (isDesktop()) {
                mainNavLinks.classList.remove('is-open');
                menuButton.setAttribute('aria-expanded', 'false');
            } else {
                closeMobileMenu();
            }
        };

        menuButton.addEventListener('click', () => {
            if (isDesktop()) {
                return;
            }

            const opened = mainNavLinks.classList.toggle('is-open');
            menuButton.setAttribute('aria-expanded', opened ? 'true' : 'false');
        });

        mainNavLinks.querySelectorAll('a').forEach((link) => {
            link.addEventListener('click', () => {
                if (window.innerWidth < 1024) {
                    closeMobileMenu();
                }
            });
        });

        window.addEventListener('resize', () => {
            syncMenuState();
        });

        syncMenuState();
    }
}
