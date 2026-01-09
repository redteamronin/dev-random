import requests
from bs4 import BeautifulSoup
import os
import time
from urllib.parse import urljoin, urlparse
import re

class PhraekScraper:
    def __init__(self, base_url="https://phrack.org", output_dir="phrack_archive"):
        self.base_url = base_url
        self.output_dir = output_dir
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        })
        
    def create_directories(self):
        """Create directories for storing scraped content"""
        os.makedirs(self.output_dir, exist_ok=True)
        os.makedirs(os.path.join(self.output_dir, 'issues'), exist_ok=True)
        os.makedirs(os.path.join(self.output_dir, 'css'), exist_ok=True)
        os.makedirs(os.path.join(self.output_dir, 'images'), exist_ok=True)
        os.makedirs(os.path.join(self.output_dir, 'dl'), exist_ok=True)
        
    def fetch_page(self, url):
        """Fetch a page with error handling"""
        try:
            response = self.session.get(url, timeout=30)
            response.raise_for_status()
            return response.text
        except requests.RequestException as e:
            print(f"Error fetching {url}: {e}")
            return None
    
    def fetch_binary(self, url):
        """Fetch binary content like images"""
        try:
            response = self.session.get(url, timeout=30)
            response.raise_for_status()
            return response.content
        except requests.RequestException as e:
            print(f"Error fetching {url}: {e}")
            return None
            
    def save_file(self, content, filepath):
        """Save content to a file"""
        os.makedirs(os.path.dirname(filepath), exist_ok=True)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Saved: {filepath}")
    
    def save_binary(self, content, filepath):
        """Save binary content to a file"""
        os.makedirs(os.path.dirname(filepath), exist_ok=True)
        with open(filepath, 'wb') as f:
            f.write(content)
        print(f"Saved: {filepath}")
        
    def download_css(self):
        """Download CSS files"""
        css_url = urljoin(self.base_url, '/style.css')
        css_content = self.fetch_page(css_url)
        if css_content:
            self.save_file(css_content, os.path.join(self.output_dir, 'css', 'style.css'))
    
    def download_images_from_html(self, html, base_url):
        """Download images referenced in HTML"""
        soup = BeautifulSoup(html, 'html.parser')
        
        for img in soup.find_all('img'):
            img_url = img.get('src')
            if img_url:
                full_url = urljoin(base_url, img_url)
                parsed = urlparse(full_url)
                
                # Create local path
                if parsed.path.startswith('/'):
                    local_path = os.path.join(self.output_dir, parsed.path.lstrip('/'))
                else:
                    local_path = os.path.join(self.output_dir, 'images', os.path.basename(parsed.path))
                
                # Download if not already downloaded
                if not os.path.exists(local_path):
                    img_content = self.fetch_binary(full_url)
                    if img_content:
                        self.save_binary(img_content, local_path)
            
    def get_issue_numbers(self):
        """Extract all issue numbers from the main page"""
        html = self.fetch_page(self.base_url)
        if not html:
            return []
            
        soup = BeautifulSoup(html, 'html.parser')
        issue_numbers = set()
        
        # Find all links that match /issues/NUMBER/
        for link in soup.find_all('a', href=True):
            href = link['href']
            match = re.search(r'/issues/(\d+)/', href)
            if match:
                issue_numbers.add(int(match.group(1)))
                
        return sorted(issue_numbers)
        
    def get_articles_from_issue(self, issue_num):
        """Get all article links for a specific issue"""
        # Try the first article to see the issue structure
        first_article_url = f"{self.base_url}/issues/{issue_num}/1.html"
        html = self.fetch_page(first_article_url)
        
        if not html:
            return []
        
        soup = BeautifulSoup(html, 'html.parser')
        article_links = set()
        
        # Add the first article
        article_links.add(first_article_url)
        
        # Find all links in the same issue
        for link in soup.find_all('a', href=True):
            href = link['href']
            # Match articles in this issue: /issues/72/1.html, /issues/72/6_md.html, etc.
            if re.match(rf'/issues/{issue_num}/\d+.*\.html', href):
                full_url = urljoin(first_article_url, href)
                article_links.add(full_url)
                
        return list(article_links)
        
    def process_html(self, html, base_url):
        """Process HTML to update links to work locally"""
        soup = BeautifulSoup(html, 'html.parser')
        
        # Update CSS links
        for link in soup.find_all('link', rel='stylesheet'):
            if link.get('href'):
                # Make CSS path relative from issues directory
                link['href'] = '../css/style.css'
                
        # Update image sources
        for img in soup.find_all('img'):
            if img.get('src'):
                src = img['src']
                # Keep the path structure but make it relative
                if src.startswith('/'):
                    img['src'] = '..' + src
                    
        # Update internal links
        for a in soup.find_all('a', href=True):
            href = a['href']
            if href.startswith('/issues/'):
                # Convert /issues/72/1.html to issues_72_1.html
                a['href'] = href.replace('/issues/', '').replace('/', '_')
            elif href.startswith('/'):
                # Other internal links, make relative
                a['href'] = '..' + href
                
        return str(soup)
        
    def scrape_index(self):
        """Scrape the main index page"""
        html = self.fetch_page(self.base_url)
        if html:
            # Download images from index
            self.download_images_from_html(html, self.base_url)
            
            # Process and save
            processed_html = self.process_html(html, self.base_url)
            self.save_file(processed_html, os.path.join(self.output_dir, 'index.html'))
        
    def scrape_article(self, url):
        """Scrape a single article"""
        html = self.fetch_page(url)
        if not html:
            return
        
        # Download images from article
        self.download_images_from_html(html, url)
            
        # Create filename from URL: /issues/72/1.html -> issues_72_1.html
        parsed = urlparse(url)
        path = parsed.path.strip('/')
        filename = path.replace('issues/', 'issues_').replace('/', '_')
        
        # Ensure .html extension
        if not filename.endswith('.html'):
            filename += '.html'
            
        filepath = os.path.join(self.output_dir, 'issues', filename)
        
        processed_html = self.process_html(html, url)
        self.save_file(processed_html, filepath)
        
    def scrape_all(self, delay=1):
        """Scrape all content from Phrack.org"""
        """Print statements are verbose, remove if annoying"""
        print("Starting Phrack.org scraper...")
        self.create_directories()
        
        # Download CSS
        print("\nDownloading CSS...")
        self.download_css()
        
        # Download main index
        print("\nDownloading main index page...")
        self.scrape_index()
        
        # Get all issue numbers
        print("\nFinding all issues...")
        issue_numbers = self.get_issue_numbers()
        print(f"Found {len(issue_numbers)} issues: {min(issue_numbers)} to {max(issue_numbers)}")
        
        # Collect all article links
        all_articles = []
        for issue_num in issue_numbers:
            print(f"\nFinding articles in issue {issue_num}...")
            articles = self.get_articles_from_issue(issue_num)
            print(f"  Found {len(articles)} articles in issue {issue_num}")
            all_articles.extend(articles)
            time.sleep(delay)
            
        print(f"\n{'='*60}")
        print(f"Total articles found: {len(all_articles)}")
        print(f"{'='*60}\n")
        
        # Download all articles
        print("Downloading articles...")
        for i, article_url in enumerate(all_articles, 1):
            print(f"[{i}/{len(all_articles)}] {article_url}")
            self.scrape_article(article_url)
            time.sleep(delay)
            
        print(f"\n{'='*60}")
        print(f"✓ Scraping complete!")
        print(f"{'='*60}")
        print(f"Files saved to: {self.output_dir}")
        print(f"  - Main index: {os.path.join(self.output_dir, 'index.html')}")
        print(f"  - All articles: {os.path.join(self.output_dir, 'issues/')}")
        print(f"  - Total articles: {len(all_articles)}")

if __name__ == "__main__":
    scraper = PhraekScraper()
    scraper.scrape_all(delay=1)  # 1 second delay between requests
